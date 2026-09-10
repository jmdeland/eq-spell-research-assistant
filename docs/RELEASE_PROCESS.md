# Release Process

1. Start from the stable production source tree.
2. Run syntax/static validation.
3. Create the versioned ZIP.
4. Calculate SHA-256 for the ZIP.
5. Create a GitHub Release tagged `vX.Y.Z`.
6. Attach the ZIP to the release.
7. Publish/update a small stable update manifest containing version, download URL, release-notes URL, and SHA-256.
8. Keep experimental demo builds separate from stable releases.

Do not publish local configuration containing personal paths or character-specific debug captures.
