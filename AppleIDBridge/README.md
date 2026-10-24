# Apple ID signing bridge

The app embeds the pinned Impactor source and applies its local patches through
`apply-patches.sh` before building the framework. Keep the gitlink pinned; local
changes belong in reviewed patch files, not an unpushed submodule commit.

The default Anisette service is Mac-backed and speaks the existing v3 protocol.
The service supplies its client description and User-Agent; header lookup preserves
value case and keeps transport metadata out of the authentication payload. TLS
certificate validation is enabled. Provisioning state is isolated by service host
in the app's existing private state directory. Existing sessions and state are not
deleted or migrated.

Only failures obtaining initial device data may advance to the next service.
Apple credential-exchange failures stop immediately. Diagnostics retain the stage
and numeric Apple error, without response text, credentials, codes or header values.

Run `bash AppleIDBridge/test-auth.sh` from the repository root for offline regression
tests. They use fictional data and never provision or authenticate an account.
The Swift Core tests and final iPhone framework/app build require the Mac CI runner.
Passing offline tests is not proof of live Apple sign-in acceptance.
