.PHONY: lint security check

# Linting with ruff (fast Python linter)
# Output format optimized for GitHub Actions annotations
lint:
	@echo "Running ruff linter..."
	ruff check . --output-format=github

# Security scanning with semgrep
# Uses auto config for community-maintained rules
# --error flag ensures CI fails on findings
security:
	@echo "Running semgrep security scan..."
	semgrep --config auto --error --severity WARNING .

# Run all checks (convenience target)
check: lint security
