package service

import "testing"

func TestSecretCipherRoundTrip(t *testing.T) {
	cipher := newSecretCipher("a-stable-key")
	encrypted, err := cipher.encrypt("secret-api-key")
	if err != nil {
		t.Fatal(err)
	}
	if encrypted == "secret-api-key" {
		t.Fatal("secret was not encrypted")
	}
	plain, err := cipher.decrypt(encrypted)
	if err != nil {
		t.Fatal(err)
	}
	if plain != "secret-api-key" {
		t.Fatalf("unexpected plaintext: %q", plain)
	}
}
