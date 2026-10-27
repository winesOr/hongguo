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
