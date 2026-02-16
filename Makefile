# Docker Hub configuration
IMAGE = docker.io/johanies/epos257
TAG   = $(shell git rev-parse --short HEAD)

# Server configuration
SERVER  = deploy@app5
APP_DIR = ~/apps/epos257

# Usage:
# 1. Add DOCKER_USERNAME and DOCKER_PASSWORD to your .env file
# 2. make build

login:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found"; \
		echo "Create .env with DOCKER_USERNAME and DOCKER_PASSWORD"; \
		exit 1; \
	fi
	export $$(grep -E '^DOCKER_' .env | xargs) && \
	export DOCKER_CONFIG="$$(mktemp -d)" && \
	printf '%s' "$$DOCKER_PASSWORD" | docker login --username "$$DOCKER_USERNAME" --password-stdin docker.io

build:
	docker build -t $(IMAGE):$(TAG) -t $(IMAGE):latest .
	docker push $(IMAGE):$(TAG)
	docker push $(IMAGE):latest

build-on-server:
	ssh $(SERVER) 'cd $(APP_DIR) && \
		git pull origin main && \
		export $$(grep -E "^DOCKER_" .env.prod | xargs) && \
		export DOCKER_CONFIG="$$(mktemp -d)" && \
		printf "%s" "$$DOCKER_PASSWORD" | docker login --username "$$DOCKER_USERNAME" --password-stdin docker.io && \
		docker build --no-cache -t $(IMAGE):$(TAG) -t $(IMAGE):latest . && \
		docker push $(IMAGE):$(TAG) && \
		docker push $(IMAGE):latest'

dev-up:
	docker compose up -d db redis

prod-pull:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  export ENV_FILE=.env.prod TAG=$(TAG) && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml pull web'

prod-up:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  export ENV_FILE=.env.prod TAG=$(TAG) && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate web'

migrate:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  export ENV_FILE=.env.prod TAG=$(TAG) && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d db redis && \
	  sleep 5 && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm web bin/rails db:migrate'

# Seed data na produkci s dvojitým potvrzením
seed-prod:
	@echo "⚠️  POZOR: Chystáš se spustit seed data na PRODUKČNÍM serveru!"
	@echo "📊 Toto smaže a znovu vytvoří všechna seed data."
	@echo ""
	@echo "🔴 Server: $(SERVER)"
	@echo "   Adresář: $(APP_DIR)"
	@echo "   Tag: $(TAG)"
	@echo ""
	@read -p "❓ Opravdu chceš pokračovat? Napiš 'ANO' pro potvrzení: " confirm && \
	if [ "$$confirm" = "ANO" ]; then \
		echo ""; \
		echo "🔴 FINÁLNÍ POTVRZENÍ:"; \
		echo "   Server: $(SERVER)"; \
		echo "   Adresář: $(APP_DIR)"; \
		echo "   Tag: $(TAG)"; \
		echo ""; \
		read -p "❓ Poslední šance! Napiš 'SEED' pro spuštění: " final && \
		if [ "$$final" = "SEED" ]; then \
			echo "🚀 Spouštím seed data..."; \
			ssh $(SERVER) 'cd $(APP_DIR) && \
				export ENV_FILE=.env.prod TAG=$(TAG) && \
				docker compose -f docker-compose.yml -f docker-compose.prod.yml exec web bundle exec rails db:seed'; \
			echo "✅ Seed data úspěšně načtena!"; \
		else \
			echo "❌ Zrušeno - nesprávné potvrzení"; \
		fi; \
	else \
		echo "❌ Zrušeno - nesprávné potvrzení"; \
	fi


# Lokální testování
local-dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d db redis web
	@echo "Starting local development server with hot reload..."
	@echo "App is running at http://localhost:3000"
	@echo "Changes in app/, config/, db/, lib/ will be reflected immediately"
	@echo "Press Ctrl+C to stop"

local-docker-build:
	docker build -t $(IMAGE):test .

local-stop:
	docker compose down

# Produkční test
prod-build:
	docker build -t $(IMAGE):$(TAG) .

prod-db-setup:
	docker compose up -d db redis
	sleep 3
	docker run --rm --network epos257_default \
		-e DATABASE_URL=postgresql://postgres:postgres@db:5432/epos257_production \
		-e RAILS_ENV=production \
		-e SECRET_KEY_BASE=dummy_key_for_production \
		$(IMAGE):$(TAG) bin/rails db:create
	docker run --rm --network epos257_default \
		-e DATABASE_URL=postgresql://postgres:postgres@db:5432/epos257_production \
		-e RAILS_ENV=production \
		-e SECRET_KEY_BASE=dummy_key_for_production \
		$(IMAGE):$(TAG) bin/rails db:migrate
	docker run --rm --network epos257_default \
		-e DATABASE_URL=postgresql://postgres:postgres@db:5432/epos257_production \
		-e RAILS_ENV=production \
		-e SECRET_KEY_BASE=dummy_key_for_production \
		$(IMAGE):$(TAG) bin/rails runner "User.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password') unless User.exists?(email: 'admin@example.com')"

prod-test:
	docker run --rm -p 3100:3000 --network epos257_default \
		-e DATABASE_URL=postgresql://postgres:postgres@db:5432/epos257_production \
		-e REDIS_URL=redis://redis:6379/0 \
		-e RAILS_ENV=production \
		-e SECRET_KEY_BASE=dummy_key_for_production \
		$(IMAGE):$(TAG)

prod-full-test: prod-build prod-db-setup prod-test
	@echo "Production app running on http://localhost:3100"
	@echo "Press Ctrl+C to stop"

deploy: build-on-server prod-pull migrate prod-up
	@echo "Deployed $(IMAGE):$(TAG)"

# Rychlý deploy pro menší změny (git pull + restart)
quick-deploy:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  git pull origin main && \
	  export ENV_FILE=.env.prod && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml restart web'
	@echo "Quick deploy completed"

# Produkční logy
logs:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  export ENV_FILE=.env.prod && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=100 -f web'

logs-all:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  export ENV_FILE=.env.prod && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=100 -f'

logs-static:
	ssh $(SERVER) 'cd $(APP_DIR) && \
	  export ENV_FILE=.env.prod && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=200 web'

# Synchronizace databáze a souborů ze serveru
sync_db:
	@echo "🔄 Synchronizuji databázi a soubory ze serveru..."
	@echo ""
	@echo "📦 1/5 Vytvářím zálohu lokální databáze..."
	@mkdir -p tmp/db_backups
	@BACKUP_FILE="tmp/db_backups/backup_$$(date +%Y%m%d_%H%M%S).sql" && \
	PGPASSWORD=postgres pg_dump -h localhost -p 5432 -U postgres epos257_development > $$BACKUP_FILE && \
	echo "✅ Záloha uložena: $$BACKUP_FILE"
	@echo ""
	@echo "📥 2/5 Stahuji produkční databázi ze serveru..."
	@ssh $(SERVER) 'cd $(APP_DIR) && \
		export ENV_FILE=.env.prod && \
		docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T db \
		pg_dump -U postgres epos257_production' > tmp/prod_dump.sql
	@echo "✅ Produkční databáze stažena"
	@echo ""
	@echo "🗑️  3/5 Resetuji lokální databázi..."
	@PGPASSWORD=postgres dropdb -h localhost -p 5432 -U postgres --if-exists epos257_development
	@PGPASSWORD=postgres createdb -h localhost -p 5432 -U postgres epos257_development
	@echo "✅ Databáze vytvořena"
	@echo ""
	@echo "📝 4/5 Importuji produkční data..."
	@PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres epos257_development < tmp/prod_dump.sql > /dev/null
	@rm tmp/prod_dump.sql
	@echo "✅ Data naimportována"
	@echo ""
	@echo "📁 5/5 Synchronizuji storage adresář..."
	@echo "   Zdroj: $(SERVER):$(APP_DIR)/storage/"
	@echo "   Cíl: ./storage/"
	@rsync -avz --progress $(SERVER):$(APP_DIR)/storage/ ./storage/
	@echo "✅ Storage synchronizován"
	@echo ""
	@echo "🎉 Hotovo! Databáze i soubory jsou synchronizovány ze serveru."

# Nahrání lokální databáze a souborů na server (opak sync_db)
push_db:
	@echo "⚠️  POZOR: Chystáš se nahrát LOKÁLNÍ databázi na PRODUKČNÍ server!"
	@echo "📊 Toto přepíše:"
	@echo "   - Celou produkční databázi"
	@echo "   - Všechny soubory ve storage"
	@echo ""
	@echo "🔴 Server: $(SERVER)"
	@echo "   Adresář: $(APP_DIR)"
	@echo ""
	@read -p "❓ Opravdu chceš pokračovat? Napiš 'ANO' pro potvrzení: " confirm && \
	if [ "$$confirm" = "ANO" ]; then \
		echo ""; \
		echo "🔴 FINÁLNÍ POTVRZENÍ:"; \
		read -p "❓ Poslední šance! Napiš 'PUSH' pro nahrání: " final && \
		if [ "$$final" = "PUSH" ]; then \
			echo ""; \
			echo "🔄 Zahajuji nahrávání..."; \
			echo ""; \
			echo "📦 1/6 Vytvářím zálohu produkční databáze..."; \
			ssh $(SERVER) 'cd $(APP_DIR) && \
				mkdir -p tmp/db_backups && \
				export ENV_FILE=.env.prod && \
				docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T db \
				pg_dump -U postgres epos257_production > tmp/db_backups/backup_$$(date +%Y%m%d_%H%M%S).sql'; \
			echo "✅ Záloha vytvořena na serveru"; \
			echo ""; \
			echo "📤 2/6 Dumpuji lokální databázi..."; \
			mkdir -p tmp; \
			PGPASSWORD=postgres pg_dump -h localhost -p 5432 -U postgres epos257_development > tmp/local_dump.sql; \
			echo "✅ Lokální databáze dumpnuta"; \
			echo ""; \
			echo "🚀 3/6 Nahrávám dump na server..."; \
			scp tmp/local_dump.sql $(SERVER):$(APP_DIR)/tmp/; \
			rm tmp/local_dump.sql; \
			echo "✅ Dump nahrán"; \
			echo ""; \
			echo "🗑️  4/6 Resetuji produkční databázi..."; \
			ssh $(SERVER) 'cd $(APP_DIR) && \
				export ENV_FILE=.env.prod && \
				docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T db \
				dropdb -U postgres --if-exists epos257_production && \
				docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T db \
				createdb -U postgres epos257_production'; \
			echo "✅ Databáze vytvořena"; \
			echo ""; \
			echo "📝 5/6 Importuji lokální data na server..."; \
			ssh $(SERVER) 'cd $(APP_DIR) && \
				export ENV_FILE=.env.prod && \
				docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T db \
				psql -U postgres epos257_production < tmp/local_dump.sql > /dev/null && \
				rm tmp/local_dump.sql'; \
			echo "✅ Data naimportována"; \
			echo ""; \
			echo "📁 6/6 Synchronizuji storage adresář na server..."; \
			echo "   Zdroj: ./storage/"; \
			echo "   Cíl: $(SERVER):$(APP_DIR)/storage/"; \
			rsync -avz --progress --delete ./storage/ $(SERVER):$(APP_DIR)/storage/; \
			echo "✅ Storage synchronizován"; \
			echo ""; \
			echo "🎉 Hotovo! Lokální databáze a soubory nahrány na server."; \
			echo "⚠️  Nezapomeň restartovat server: make prod-up"; \
		else \
			echo "❌ Zrušeno - nesprávné potvrzení"; \
		fi; \
	else \
		echo "❌ Zrušeno - nesprávné potvrzení"; \
	fi
