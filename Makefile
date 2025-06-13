# Makefile

ZIP_NAME=lambda.zip
LAMBDA_DIR=lambda
PROJECT_DIR=$(CURDIR)

.PHONY: all build clean

all: build

build:
	@echo "🔧 Empaquetando Lambda en $(ZIP_NAME)..."
	@rm -f $(PROJECT_DIR)/$(ZIP_NAME)
	@{ \
		BUILD_DIR=$$(mktemp -d); \
		echo "📦 Usando directorio temporal: $$BUILD_DIR"; \
		pip install -r $(LAMBDA_DIR)/requirements.txt -t $$BUILD_DIR; \
		rsync -av --exclude=".venv" --exclude="__pycache__" --exclude="*.pyc" --exclude="*.pyo" --exclude="*.DS_Store" $(LAMBDA_DIR)/ $$BUILD_DIR/; \
		cd $$BUILD_DIR && zip -r9 "$(PROJECT_DIR)/$(ZIP_NAME)" .; \
		rm -rf $$BUILD_DIR; \
		echo "✅ Lambda empaquetada en $(ZIP_NAME)"; \
	}

clean:
	@echo "🧹 Limpiando archivos..."
	@rm -f $(PROJECT_DIR)/$(ZIP_NAME)
