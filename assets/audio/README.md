# Original placeholder chase loop

`chase-placeholder.wav` is an original, synthesized heartbeat and dissonant bass
loop created for this prototype. It contains no sampled recordings or third-party
music. It is eight seconds long, mono, 44.1 kHz, 16-bit PCM; peak amplitude is 78%
of full scale. The game fades this loop according to distance from the OG Chad.

Regenerate the exact file from the repository root:

```sh
python3 tools/generate_chase_audio.py
```

Roblox does not load a repository WAV directly into a live `Sound`. Upload this
file as an audio asset using Roblox Studio's Asset Manager or Creator Dashboard,
wait for any moderation, and grant the published experience permission to use it.
Then set the shared configuration's chase sound asset ID to the uploaded
`rbxassetid://...` value. The default configuration deliberately contains no
third-party audio ID. Audio upload and permission approval require the experience
owner's Roblox account and cannot be performed by the repository build.
