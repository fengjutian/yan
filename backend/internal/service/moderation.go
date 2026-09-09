package service

import (
	"errors"
	"strings"
)

var ErrUnsafePrompt = errors.New("unsafe prompt")

var blockedPromptTerms = []string{
	"儿童色情", "未成年裸照", "性侵", "强奸", "虐杀", "肢解",
	"制作炸弹", "恐怖袭击", "仇恨屠杀", "身份证正反面", "银行卡密码",
}

func validateSafePrompt(prompt string) error {
	normalized := strings.ToLower(strings.ReplaceAll(prompt, " ", ""))
	for _, term := range blockedPromptTerms {
		if strings.Contains(normalized, term) {
			return ErrUnsafePrompt
		}
	}
	return nil
}
