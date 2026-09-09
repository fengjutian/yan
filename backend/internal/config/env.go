package config

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// loadEnvFile loads local configuration without overriding variables already
// supplied by the process (for example, by Docker Compose).
func loadEnvFile() error {
	if configured := strings.TrimSpace(os.Getenv("ENV_FILE")); configured != "" {
		if err := readEnvFile(configured); err != nil {
			return fmt.Errorf("load ENV_FILE %q: %w", configured, err)
		}
		return nil
	}

	for _, candidate := range []string{".env.local", "../.env.local", ".env", "../.env"} {
		if err := readEnvFile(candidate); err == nil {
			return nil
		} else if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("load environment file %q: %w", candidate, err)
		}
	}
	return nil
}

func readEnvFile(path string) error {
	file, err := os.Open(filepath.Clean(path))
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(strings.TrimPrefix(scanner.Text(), "\ufeff"))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		key, value, found := strings.Cut(line, "=")
		key = strings.TrimSpace(key)
		if !found || key == "" {
			return fmt.Errorf("line %d: expected KEY=VALUE", lineNumber)
		}
		value = strings.TrimSpace(value)
		if len(value) >= 2 && ((value[0] == '"' && value[len(value)-1] == '"') ||
			(value[0] == '\'' && value[len(value)-1] == '\'')) {
			if value[0] == '"' {
				value, err = strconv.Unquote(value)
				if err != nil {
					return fmt.Errorf("line %d: invalid quoted value: %w", lineNumber, err)
				}
			} else {
				value = value[1 : len(value)-1]
			}
		}
		if _, exists := os.LookupEnv(key); !exists {
			if err := os.Setenv(key, value); err != nil {
				return fmt.Errorf("line %d: set %s: %w", lineNumber, key, err)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read: %w", err)
	}
	return nil
}
