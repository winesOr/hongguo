package core

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/beilunyang/openhongguo/adapters"
	"github.com/beilunyang/openhongguo/adapters/httptransport"
	"github.com/beilunyang/openhongguo/adapters/memstore"
	"github.com/beilunyang/openhongguo/sdk"
	"github.com/beilunyang/openhongguo/sdk/model"
)

// 红果 App 官方取流（openhongguo 匿名 SDK）。
//
// 本项目自带的 signHongguoRequest 只实现了 x-gorgon，字节网关在
// /novel/player/video_model 上要求 x-gorgon + x-ladon + x-helios + x-medusa 全套签名，
// 因此旧通道必然被拦（HTTP 200 + 空包体）。
//
// openhongguo 用纯 Go 复刻了整套签名（含 SM3、变种 MD5、protobuf、AES 变体），
// 并用 CENC spade_a 反混淆还原内容密钥，所以这条通道能拿到官方全清晰度
// （实测 360p/480p/540p/720p/1080p）以及第 51 集之后的内容。
//
// SDK 以匿名设备身份请求，设备档案落盘到 dataDir，跨启动复用；
// 服务端拒绝设备时（ErrDeviceRejected）自动重置设备后重试一次。

const hongguoSDKProfileName = "hongguo_anonymous.json"

type hongguoSDKState struct {
	mu      sync.Mutex
	client  *sdk.Client
	profile string
}

func (downloader *Downloader) hongguoSDKClient() (*sdk.Client, error) {
	downloader.hongguoSDK.mu.Lock()
	defer downloader.hongguoSDK.mu.Unlock()
	profile := ""
	if dir := strings.TrimSpace(downloader.cfg.dataDir); dir != "" {
		profile = filepath.Join(dir, hongguoSDKProfileName)
	}
	if downloader.hongguoSDK.client != nil && downloader.hongguoSDK.profile == profile {
		return downloader.hongguoSDK.client, nil
	}
	var client *sdk.Client
	var err error
	if profile == "" {
		client, err = sdk.NewClient(sdk.Options{Transport: httptransport.New(), ProfileStore: memstore.New()})
	} else {
		if mkErr := os.MkdirAll(filepath.Dir(profile), 0o700); mkErr != nil {
			return nil, fmt.Errorf("红果设备档案目录不可用: %w", mkErr)
		}
		client, err = adapters.NewClient(profile, sdk.Options{RetryAttempts: 3})
	}
	if err != nil {
		return nil, fmt.Errorf("红果 SDK 初始化失败: %w", err)
	}
	downloader.hongguoSDK.client = client
	downloader.hongguoSDK.profile = profile
	return client, nil
}

// hongguoSDKPlayback 解析一集的官方播放模型。设备被拒时重置匿名设备并重试一次。
func (downloader *Downloader) hongguoSDKPlayback(ctx context.Context, client *sdk.Client, videoID string) (*model.Playback, error) {
	playback, err := client.ResolvePlayback(ctx, videoID, sdk.PlaybackOptions{})
	if playback != nil && (err == nil || errors.Is(err, sdk.ErrDRMProtected)) {
		return playback, err
	}
	if errors.Is(err, sdk.ErrDeviceRejected) {
		if resetErr := client.ResetDevice(ctx); resetErr == nil {
			return client.ResolvePlayback(ctx, videoID, sdk.PlaybackOptions{})
		}
	}
	if err == nil {
		err = errors.New("红果 SDK 未返回播放模型")
	}
	return nil, err
}

func (downloader *Downloader) resolveHongguoSDKMedia(ctx context.Context, videoID string) (providerMedia, error) {
	if !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果视频 ID 无效")
	}
	client, err := downloader.hongguoSDKClient()
	if err != nil {
		return providerMedia{}, err
	}
	playback, resolveErr := downloader.hongguoSDKPlayback(ctx, client, videoID)
	if playback == nil {
		return providerMedia{}, resolveErr
	}
	var contentKey []byte
	if playback.Protected {
		key, keyErr := sdk.ContentKey(playback)
		if keyErr != nil {
			return providerMedia{}, fmt.Errorf("红果内容密钥不可用: %w", keyErr)
		}
		decoded, decodeErr := hex.DecodeString(strings.TrimSpace(key.Hex))
		if decodeErr != nil || len(decoded) != 16 {
			return providerMedia{}, errors.New("红果内容密钥格式无效")
		}
		contentKey = decoded
	}
	duration := time.Duration(playback.DurationSeconds) * time.Second
	type scoredMedia struct {
		media providerMedia
		score int
	}
	var choices []scoredMedia
	for _, stream := range playback.Streams {
		// 分段（DASH）表示形式需要 init/index 区间拼装，本地代理只处理单文件流。
		if stream.Dash {
			continue
		}
		mainURL := strings.TrimSpace(stream.URL)
		if !isProviderHTTPMediaURL(mainURL) {
			continue
		}
		codec := strings.ToLower(strings.TrimSpace(stream.Codec))
		if codec == "bytevc2" {
			continue
		}
		height := stream.Height
		if height <= 0 {
			height, _ = strconv.Atoi(hongguoQualityNumber.FindString(stream.Definition))
		}
		score := height * 10
		if codec == "h264" || codec == "avc1" {
			score++
		}
		media := providerMedia{
			URL:       mainURL,
			Referer:   "https://novel.snssdk.com/",
			UserAgent: hongguoAppUserAgent,
			Duration:  duration,
			CENCKey:   contentKey,
			Quality:   height,
		}
		choices = append(choices, scoredMedia{media: media, score: score})
		if backup := strings.TrimSpace(stream.BackupURL); isProviderHTTPMediaURL(backup) {
			alternative := media
			alternative.URL = backup
			choices = append(choices, scoredMedia{media: alternative, score: score - 1})
		}
	}
	if len(choices) == 0 {
		if resolveErr != nil {
			return providerMedia{}, resolveErr
		}
		return providerMedia{}, errors.New("红果 App 未返回可用的媒体地址")
	}
	sort.SliceStable(choices, func(i, j int) bool { return choices[i].score > choices[j].score })
	selected := choices[0].media
	for _, choice := range choices {
		selected.Variants = append(selected.Variants, choice.media)
	}
	return selected, nil
}
