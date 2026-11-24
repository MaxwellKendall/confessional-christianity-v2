Test-only RSA keys for `test/support/cognitoJwt.ts`. They sign fake Cognito
tokens that a verifier given the matching public key accepts. They are not used
by anything outside the test suite and protect nothing.

They are committed instead of generated because RSA key generation is a random
prime search that took 0.3-2 s per key on an idle Mac and over 10 s under load,
which pushed tests past vitest's timeouts (TKL-981).
