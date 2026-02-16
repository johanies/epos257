# check=error=true

# Production Dockerfile (multi-stage). Build lokálně/CI, server jen pull→run.

FROM ruby:3.3.4 AS base

WORKDIR /rails

# Základní systémové balíčky
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Prostředí pro prod Bundler
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development test"

# ---------- Build stage ----------
FROM base AS build

# Balíčky pro kompilaci gemů
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Ruby závislosti
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "$BUNDLE_PATH"/ruby/*/cache "$BUNDLE_PATH"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Aplikace
COPY . .

# Bootsnap precompile pro rychlejší boot
RUN bundle exec bootsnap precompile app/ lib/

RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

# ---------- Final stage ----------
FROM base

# Přenést nainstalované gemy a appku
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Kopírovat precompilované assety
COPY --from=build /rails/public/assets /rails/public/assets

# Ne-root uživatel a přístup k runtime adresářům
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p app/assets/builds public/assets && \
    chown -R rails:rails db log storage tmp app/assets/builds public/assets
USER 1000:1000

# Entrypoint připraví DB (Rails 7/8 default)
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Server přes Thruster (přebij v Compose, když chceš)
EXPOSE 3000
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
