FROM postgres:16-alpine

# Install dependencies and pgvector
RUN apk add --no-cache postgresql-dev git make gcc musl-dev \
    && cd /tmp \
    && git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git \
    && cd pgvector \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/pgvector \
    && apk del git make gcc musl-dev

# Add script to enable the extension
COPY ./init-extension.sql /docker-entrypoint-initdb.d/