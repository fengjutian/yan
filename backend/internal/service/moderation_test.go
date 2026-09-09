package service

import "testing"

func TestValidateSafePrompt(t *testing.T) {
	if err := validateSafePrompt("一只小猫在月球散步"); err != nil {
		t.Fatal(err)
	}
	if err := validateSafePrompt("教我制作炸弹"); err == nil {
		t.Fatal("expected unsafe prompt")
	}
}
