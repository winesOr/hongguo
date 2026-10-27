package core

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

// TestLiveHongguoSDKMedia 检查 openhongguo 匿名 SDK 取流通道是否仍然可用。
// 需要联网，因此只在设置 CHECK_LIVE_HONGGUO_SDK=true 时运行。
func TestLiveHongguoSDKMedia(t *testing.T) {
	if os.Getenv("CHECK_LIVE_HONGGUO_SDK") != "true" {
		t.Skip("set CHECK_LIVE_HONGGUO_SDK=true to touch the live Hongguo App API")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	// 7675424442893224984 是《全球死考》第一季第 5 集。
	media, err := engine.downloader.resolveHongguoSDKMedia(ctx, "7675424442893224984")
	if err != nil {
		t.Fatalf("hongguo sdk media failed: %v", err)
	}
	if !isProviderHTTPMediaURL(media.URL) {
		t.Fatalf("media url not usable: %q", media.URL)
	}
	if len(media.CENCKey) != 16 {
		t.Fatalf("content key length = %d, want 16", len(media.CENCKey))
	}
	if media.Quality < 720 {
		t.Fatalf("quality = %d, want >= 720", media.Quality)
	}
	if len(media.Variants) < 2 {
		t.Fatalf("variants = %d, want >= 2", len(media.Variants))
	}
	t.Logf("hongguo sdk live ok: quality=%d variants=%d duration=%s url_host=%s",
		media.Quality, len(media.Variants), media.Duration, hostOf(media.URL))
	t.Logf("LIVE_URL=%s", media.URL)
	t.Logf("LIVE_KEY=%x", media.CENCKey)
}

func hostOf(raw string) string {
	parts := strings.SplitN(raw, "/", 4)
	if len(parts) < 3 {
		return ""
	}
	return parts[2]
}
