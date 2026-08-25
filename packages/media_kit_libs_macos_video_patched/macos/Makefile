VERIFY=../../../dev/scripts/verify_macos_subtitle_decoders.sh

all: verify

# Local development remains buildable without Nix. Release CI installs the
# patched frameworks before CocoaPods runs; when they are absent, use the exact
# hosted MediaKit bundle as a compatibility fallback. The app-level failure
# handling will clearly reject unsupported PGS tracks in that fallback build.
UPSTREAM_VERSION=v0.6.0
UPSTREAM_SHA256=84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6
CACHE=.cache/libmpv-macos-video-default.tar.gz

Frameworks/Mpv.xcframework:
	mkdir -p .cache
	@if [ ! -f "$(CACHE)" ]; then \
		curl -fL https://github.com/media-kit/libmpv-darwin-build/releases/download/$(UPSTREAM_VERSION)/libmpv-xcframeworks_$(UPSTREAM_VERSION)_macos-universal-video-default.tar.gz -o $(CACHE).tmp; \
		shasum -a 256 -c <<< '$(UPSTREAM_SHA256)  $(CACHE).tmp'; \
		mv $(CACHE).tmp $(CACHE); \
	fi
	mkdir -p Frameworks
	rm -rf Frameworks/*.xcframework
	tar -xzf $(CACHE) --strip-components 1 -C Frameworks

Frameworks/.symlinks: Frameworks/Mpv.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv
	touch Frameworks/.symlinks

verify: Frameworks/.symlinks
	"$(VERIFY)" Frameworks --architectures-only

.PHONY: all clean verify
clean:
	rm -rf Frameworks .cache
