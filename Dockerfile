# syntax = docker/dockerfile:1

# Define a variável de versão do Ruby e utiliza a imagem slim como base
ARG RUBY_VERSION=3.1.2
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Define o diretório de trabalho
WORKDIR /app

# Variável que define o ambiente (production por padrão)
ENV RAILS_ENV="${RAILS_ENV}"

# Dependências comuns para todos os ambientes
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y curl libvips postgresql-client nodejs && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Configurações específicas para produção
ENV BUNDLE_DEPLOYMENT="1" \
  BUNDLE_PATH="/usr/local/bundle"

# Exclui os ambientes que não forem necessários para produção
# Para outros ambientes, o BUNDLE_WITHOUT pode ser redefinido no runtime
ENV BUNDLE_WITHOUT="development test"

# Fase de build para pré-compilar gems e assets
FROM base as build

# Instala pacotes necessários para compilar as gems
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config

# Copia o Gemfile e o Gemfile.lock para a imagem e instala as dependências
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copia o código da aplicação
COPY . .

# Pré-compilação de código para boot mais rápido (compartilhado por todos os ambientes)
RUN bundle exec bootsnap precompile app/ lib/

# Pré-compila os assets apenas se o ambiente for production
RUN if [ "$RAILS_ENV" = "production" ]; then SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile; fi

# Fase final de runtime
FROM base

# Copia as dependências e o código pré-compilado da fase de build
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

# Configuração de usuário não-root para maior segurança
RUN useradd -m -s /bin/bash rails && \
  chown -R rails:rails /app
USER rails

# Define o entrypoint para preparar o banco de dados (aplicável a qualquer ambiente)
ENTRYPOINT ["./bin/docker-entrypoint"]

# Expõe a porta 3000
EXPOSE 3000

# Comando padrão para iniciar o servidor, pode ser sobrescrito no runtime
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
