# Synthetic media fixtures

These three-second test patterns and 440 Hz tones were generated locally with FFmpeg's `testsrc2` and `sine` sources. They contain no third-party recordings.

```sh
ffmpeg -f lavfi -i testsrc2=size=160x90:rate=12 -f lavfi -i sine=frequency=440:sample_rate=48000 -t 3 -c:v libx264 -pix_fmt yuv420p -profile:v main -crf 32 -c:a aac -b:a 48k -movflags frag_keyframe+empty_moov+default_base_moof h264-aac.mp4
ffmpeg -i h264-aac.mp4 -vn -c:a copy -movflags +faststart aac.m4a
ffmpeg -f lavfi -i testsrc2=size=160x90:rate=12 -f lavfi -i sine=frequency=440:sample_rate=48000 -t 3 -c:v libvpx-vp9 -crf 42 -b:v 0 -c:a libopus -b:a 32k vp9-opus.webm
```

The MP4 is fragmented to exercise both ordinary video playback and Media Source Extensions. AAC is also decoded separately through Web Audio to catch builds that play H.264 silently without an audio decoder. `media.mjs --require-proprietary` requires every format to decode successfully, produce frames/audio samples, and seek.
