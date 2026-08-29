# Table of Contents <!-- omit in toc -->

- [1. Overview: Containerize a Django application](#1-overview-containerize-a-django-application)
- [2. Prerequisites](#2-prerequisites)
- [3. Create the Django project](#3-create-the-django-project)
- [4. Start with a simple `Dockerfile`](#4-start-with-a-simple-dockerfile)
- [5. Create a simple docker compose](#5-create-a-simple-docker-compose)
- [6. Create multi-stage `Dockerfile`](#6-create-multi-stage-dockerfile)
- [7. Set up a development environment](#7-set-up-a-development-environment)
  - [7.1. Update the Dockerfile](#71-update-the-dockerfile)
  - [7.2. Update Compose file (target `development` stage)](#72-update-compose-file-target-development-stage)
  - [7.3. Update Compose file (Configure Compose Watch)](#73-update-compose-file-configure-compose-watch)
    - [7.3.1. Run with Compose Watch](#731-run-with-compose-watch)
    - [7.3.2. Test Compose Watch](#732-test-compose-watch)
- [8. Using mounts to `uv sync` in `Dockerfile`](#8-using-mounts-to-uv-sync-in-dockerfile)
- [9. Setting up PostgreSQL Database](#9-setting-up-postgresql-database)
  - [9.1. Add the PostgreSQL driver](#91-add-the-postgresql-driver)
  - [9.2. Create an `.env` file](#92-create-an-env-file)
  - [9.3. Update `settings.py`](#93-update-settingspy)
  - [9.4. Add the PostgreSQL service](#94-add-the-postgresql-service)
  - [9.5. Test postgreSQL](#95-test-postgresql)
  - [9.6. Create and run migrations](#96-create-and-run-migrations)
  - [9.7. Create superuser](#97-create-superuser)
  - [9.8. Persist data through volumes](#98-persist-data-through-volumes)
  - [9.9. Finalize the compose file](#99-finalize-the-compose-file)
  - [9.10. Final test](#910-final-test)

# 1. Overview: Containerize a Django application

This guide shows how to containerize a Django application using Docker. You'll scaffold the project with `uv`, create a production-ready `Dockerfile` using a `Docker Hardened Image`, then add a development stage and `Compose` Watch for fast iteration.

# 2. Prerequisites

- You have installed the latest version of [Docker Desktop](https://tinyurl.com/2up6tvrk).
- You have [uv](https://tinyurl.com/5bdmvhn4) installed

# 3. Create the Django project

1. Create a project directory named 'django-docker' and navigate to it.
2. Initialize the project in the current directory, pinned to `Python 3.14`:

```bash
uv init --python 3.14 .
```

3. Add Django and Gunicorn, then scaffold the Django project:

```bash
uv add django gunicorn
uv run django-admin startproject config .
```

Your directory should now contain the following files:

```
├── .python-version
├── src/
│ └── docker_django/
│   └── __init__.py
├── manage.py
├── config/
│ ├── __init__.py
│ ├── asgi.py
│ ├── settings.py
│ ├── urls.py
│ └── wsgi.py
├── pyproject.toml
├── uv.lock
└── README.md
```

# 4. Start with a simple `Dockerfile`

We'll first create a simple one-stage image from a base python imgae from `Docker Hardened Images registry`.

`Docker Hardened Images` are production-ready base images maintained by Docker that minimize attack surface.

1. Open/run docker desktop
2. Sign in to the `DHI` registry to use Docker Hardened Images (default registry is `Docker hub`):

   ```bash
   docker login dhi.io
   ```

3. Create a `.dockerignore` file to exclude local artifacts from the build context:

   `.dockerignore`

   ```
   .venv/
   __pycache__/
   *.pyc
   .git/
   ```

4. Create a `Dockerfile` with the following content:

   ```dockerfile
   # Build my image from a base python image from DHI registry
   # `-dev` image includes tools needed to install packages.
   FROM dhi.io/python:3.14-alpine3.24-dev
   # Prevent Python from writing .pyc files to disk.
   ENV PYTHONDONTWRITEBYTECODE=1
   # Prevent Python from buffering stdout/stderr so logs appear immediately.
   ENV PYTHONUNBUFFERED=1
   # Set `/app` as the working directory inside the container
   WORKDIR /app
   # Install uv using python image's pip;
   # `--quiet` (optional) reduces pip's output;
   # `--root-user-action=ignore` (optional) prevents pip from warning about the root user
   RUN pip install --quiet --root-user-action=ignore uv
   # Copy the dependencies files to the working directory
   COPY pyproject.toml uv.lock ./
   # `uv sync` creates `.venv` and installs the dependencies in it.
   # `--frozen` tells uv to use the existing `uv.lock` file;
   # `--no-install-project` tells uv not to install the project
   RUN uv sync --frozen --no-install-project
   # Copy the contents into container at `/app`
   COPY . .
   # Tell python to use `.venv`
   ENV PATH="/app/.venv/bin:$PATH"
   # Expose port 8000: just a metadata (optional)
   EXPOSE 8000
   # Base command to run when the container starts
   CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
   ```

   > [!NOTE]
   > Notice `0.0.0.0:8000` rather than: `127.0.0.1:8000`.
   > Inside a container, Django needs to listen on `0.0.0.0` so that traffic coming through Docker's networking can reach it.

5. Now build the image named `django-docker` for the first time:

   ```bash
   docker build -t django-docker .
   ```

6. Then run the container from that image:

   ```bash
   docker run -p 8000:8000 django-docker
   ```

7. Open a browser and navigate to http://localhost:8000. You should see the Django welcome page.

# 5. Create a simple docker compose

1. Create a `compose.yaml` file in project root:

   ```yml
   services:
   web:
     # Build the image using Dockerfile in the current directory
     build: .
     # (optional) name the image
     image: docker-django
     ports:
       # equivalent to `docker run -p 8000:8000`
       - "8000:8000"
   ```

2. Run the application:

   From the project directory, run:

   ```bash
   docker compose up --build
   ```

   Open the browser and navigate to http://localhost:8000. You should again see the same Django welcome page, but this time with simpler `docker compose` command instead to `docker run` commands

   Press `ctrl+c` to stop the application.

# 6. Create multi-stage `Dockerfile`

Now that we have the single-stage `Dockerfile` working and `compose.yaml` working, this is the right time to introduce a simple two-stage `Dockerfile`.

Our current Dockerfile does everything in one image:

```
DHI Python -dev
install uv
create .venv
install dependencies
copy Django source
run Gunicorn
```

The problem is that the `-dev` image contains tools needed to _build_ the application, but we don't need those tools when we're merely _running_ the application.

So we split it:

```
BUILD STAGE
────────────────────────
DHI Python -dev
install uv
create .venv
install dependencies
       └────┐
            ▼
RUNTIME STAGE
────────────────────────
DHI Python runtime
copy .venv
copy Django source
run Gunicorn
```

This is the fundamental idea of a multi-stage build.

So, here is our two-stage `Dockerfile`:

```dockerfile
###### BUILD STAGE #######
# Build my image from a base python image from DHI registry
# `-dev` image includes tools needed to install packages.
FROM dhi.io/python:3.14-alpine3.24-dev AS builder
# Prevent Python from writing .pyc files to disk.
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent Python from buffering stdout/stderr so logs appear immediately.
ENV PYTHONUNBUFFERED=1
# Install uv using python image's pip;
# `--quiet` (optional) reduces pip's output;
# `--root-user-action=ignore` (optional) prevents pip from warning about the root user
RUN pip install --quiet --root-user-action=ignore uv
# Set `/app` as the working directory inside the container
WORKDIR /app
# Copy the dependencies files to the working directory
COPY pyproject.toml uv.lock ./
# `uv sync` creates `.venv` and installs the dependencies in it.
# `--frozen` tells uv to use the existing `uv.lock` file;
# `--no-install-project` tells uv not to install the project
RUN uv sync --frozen --no-install-project

###### RUNTIME STAGE #######
# Use minimal DHI image with no shell or package manager
# already runs as the nonroot user.
FROM dhi.io/python:3.14-alpine3.24
# Prevent Python from writing .pyc files to disk.
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent Python from buffering stdout/stderr so logs appear immediately.
ENV PYTHONUNBUFFERED=1
# Make executables from the copied virtual environment available on PATH.
ENV PATH="/app/.venv/bin:$PATH"
# Set `/app` as the working directory inside the container
WORKDIR /app
# Copy the pre-built virtual environment and application source code.
COPY --from=builder /app/.venv /app/.venv
# Copy the application source code into `/app`.
COPY . .
# Expose port 8000: just a metadata (optional)
EXPOSE 8000
# Run Gunicorn as the production WSGI server.
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
```

Now, run again:

```bash
docker compose up --build
```

Open the browser and navigate to http://localhost:8000. You should again see the same Django welcome page.

Press `ctrl+c` to stop the application.

# 7. Set up a development environment

The production setup uses Gunicorn and requires a full image rebuild to pick up code changes. For development, you can add a `development` stage to your `Dockerfile` that uses Django's built-in server, and configure Compose Watch to automatically sync code changes into the running container without a rebuild.

## 7.1. Update the Dockerfile

Replace your `Dockerfile` that adds a `development` stage alongside `production`:

```dockerfile
###### BUILD STAGE #######
# Build my image from a base python image from DHI registry
# `-dev` image includes tools needed to install packages.
FROM dhi.io/python:3.14-alpine3.24-dev AS builder
# Prevent Python from writing `.pyc` files to disk.
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent Python from buffering stdout/stderr so logs appear immediately.
ENV PYTHONUNBUFFERED=1
# Install uv using python image's pip;
# `--quiet` (optional) reduces pip's output;
# `--root-user-action=ignore` (optional) prevents pip from warning about the root user
RUN pip install --quiet --root-user-action=ignore uv
# Set `/app` as the working directory inside the container
WORKDIR /app
# Copy the dependencies files to the working directory
COPY pyproject.toml uv.lock ./
# `uv sync` creates `.venv` and installs the dependencies in it.
# `--frozen` tells uv to use the existing `uv.lock` file;
# `--no-install-project` tells uv not to install the project
RUN uv sync --frozen --no-install-project


###### DEVELOPMENT STAGE #######
# The development stage inherits the `-dev` image and `.venv` from the builder.
# Django's built-in server reloads when Compose Watch syncs files.
FROM builder AS development
# Make executables from the builder's `.venv` available on PATH.
ENV PATH="/app/.venv/bin:$PATH"
# Copy the application source code into `/app`.
COPY . .
# Expose port 8000: just a metadata (optional)
EXPOSE 8000
# Run Django's development server
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]


###### PRODUCTION STAGE #######
# The production stage uses the minimal runtime image, which has no shell,
# no package manager, and already runs as the nonroot user.
FROM dhi.io/python:3.14-alpine3.24 AS production
# Prevent Python from writing .pyc files to disk.
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent Python from buffering stdout/stderr so logs appear immediately.
ENV PYTHONUNBUFFERED=1
# Make executables from the builder's `.venv` available on PATH.
ENV PATH="/app/.venv/bin:$PATH"
# Set `/app` as the working directory inside the container
WORKDIR /app
# Copy the pre-built virtual environment from the builder stage.
COPY --from=builder /app/.venv /app/.venv
# Copy the application source code into `/app`.
COPY . .
# Expose port 8000: just a metadata (optional)
EXPOSE 8000
# Run Gunicorn as the production WSGI server.
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]

```

## 7.2. Update Compose file (target `development` stage)

Replace your `compose.yaml` to target the `development` stage:

```yaml
services:
  web:
    # Build the image using `Dockerfile`
    build:
      # use the current directory as the build context
      context: .
      # Build the `development` stage from the `Dockerfile` (not the `production` stage).
      target: development

    # (optional) Name the resulting image.
    image: docker-django

    ports:
      # equivalent to `docker run -p 8000:8000`
      - "8000:8000"
```

**Run**

Then run `docker compose up --build` and visit http://localhost:8000/. If you check the logs, you'll notice that this time the container is running Django's built-in development server (`runserver`) instead of Gunicorn.

## 7.3. Update Compose file (Configure Compose Watch)

Right now, `COPY . .` copies the Django source code into the image during the build. If you modify a source file on your host, the change is not automatically reflected inside the running container. We can use Compose Watch to synchronise source-code changes into the running container.

`compose.yaml`

```yaml
services:
  web:
    # Build the image using `Dockerfile`
    build:
      # use the current directory as the build context
      context: .
      # Build the `development` stage from the `Dockerfile` (not the `production` stage).
      target: development

    # (optional) Name the resulting image.
    image: docker-django

    ports:
      # equivalent to `docker run -p 8000:8000`
      - "8000:8000"

    develop:
      watch:
        # Sync source file changes directly into the container
        # so Django's dev server can reload them without a full image rebuild.
        - action: sync
          path: .
          target: /app
          # don't synchronise changes from these paths.
          ignore:
            - __pycache__/
            - "*.pyc"
            - .git/
            - .venv/
        # Rebuild the image when dependencies change.
        - action: rebuild
          path: pyproject.toml
        - action: rebuild
          path: uv.lock
```

> [!NOTE]
> The `sync` action pushes file changes directly into the running container so Django's dev server reloads them automatically. A change to `pyproject.toml` or `uv.lock` triggers a full image rebuild instead.

### 7.3.1. Run with Compose Watch

Now, start the development stack:

```bash
docker compose watch
```

Open a browser and navigate to http://localhost:8000.

If you check the logs, you'll notice "Watch enabled"

### 7.3.2. Test Compose Watch

Now let's make a small change in `config/urls.py` from the source code:

```py
from django.http import HttpResponse # new

urlpatterns = [
    # ...
    path("", lambda request: HttpResponse("Hello from Django-Docker!")),
]
```

Save the changes and look at your logs, you'll see "changes were detected". Visit http://localhost:8000 (or reload it) to see the response "Hello from Django-Docker!".

Compose Watch syncs the change into the container and Django's dev server reloads automatically. If you update `pyproject.toml`or `uv.lock`, Compose Watch triggers a full image rebuild.

Press `ctrl+c` to stop.

# 8. Using mounts to `uv sync` in `Dockerfile`

We'll update the `Dockerfile` once again with a few improvements to how dependencies are installed::

- Add `UV_LINK_MODE=copy` so `uv` copies packages instead of creating links between the cache and the virtual environment.
- Instead of permanently copying `pyproject.toml` and `uv.lock` into an image layer, make them temporarily available to `uv sync` using bind mounts.
- Use a cache mount so `uv` can reuse downloaded packages between builds.
- Add `# syntax=docker/dockerfile:1` to the top of the `Dockerfile`. This tells Docker to use the stable version `1` of the Dockerfile syntax, which supports features such as `RUN --mount`.

So, our final Dockerfile is:

```dockerfile
# syntax=docker/dockerfile:1

###### BUILD STAGE #######
# Build my image from a base python image from DHI registry
# `-dev` image includes tools needed to install packages.
FROM dhi.io/python:3.14-alpine3.24-dev AS builder
# Prevent Python from writing `.pyc` files to disk.
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent Python from buffering stdout/stderr so logs appear immediately.
ENV PYTHONUNBUFFERED=1
# Install uv using python image's pip;
# `--quiet` (optional) reduces pip's output;
# `--root-user-action=ignore` (optional) prevents pip from warning about the root user
RUN pip install --quiet --root-user-action=ignore uv
# Use copy mode since the cache and build filesystem are on different volumes.
ENV UV_LINK_MODE=copy
# Set `/app` as the working directory inside the container
WORKDIR /app
# Install dependencies into a `.venv` using `cache` and `bind` mounts
# so neither uv nor the lock files need to be copied into the image.
# `uv sync` creates `.venv` and installs the dependencies in it.
# `--frozen` tells uv to use the existing `uv.lock` file;
# `--no-install-project` tells uv not to install the project
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project


###### DEVELOPMENT STAGE #######
# The development stage inherits the `-dev` image and `.venv` from the builder.
# Django's built-in server reloads when Compose Watch syncs files.
FROM builder AS development
# Make executables from the builder's `.venv` available on PATH.
ENV PATH="/app/.venv/bin:$PATH"
# Copy the application source code into `/app`.
COPY . .
# Expose port 8000: just a metadata (optional)
EXPOSE 8000
# Run Django's development server
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]


###### PRODUCTION STAGE #######
# The production stage uses the minimal runtime image, which has no shell,
# no package manager, and already runs as the nonroot user.
FROM dhi.io/python:3.14-alpine3.24 AS production
# Prevent Python from writing .pyc files to disk.
ENV PYTHONDONTWRITEBYTECODE=1
# Prevent Python from buffering stdout/stderr so logs appear immediately.
ENV PYTHONUNBUFFERED=1
# Make executables from the builder's `.venv` available on PATH.
ENV PATH="/app/.venv/bin:$PATH"
# Set `/app` as the working directory inside the container
WORKDIR /app
# Copy the pre-built virtual environment from the builder stage.
COPY --from=builder /app/.venv /app/.venv
# Copy the application source code into `/app`.
COPY . .
# Expose port 8000: just a metadata (optional)
EXPOSE 8000
# Run Gunicorn as the production WSGI server.
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
```

Run `docker compose watch` to build and start the development environment again, then verify that the application starts successfully.

# 9. Setting up PostgreSQL Database

## 9.1. Add the PostgreSQL driver

Add the `psycopg` adapter to your project:

```bash
uv add "psycopg[binary,pool]"
```

This will add the driver to `pyproject.toml` and install it into `.venv`.

## 9.2. Create an `.env` file

Create an `.env` file with the following:

```
POSTGRES_DB=mydockerdjango
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<your-password>
POSTGRES_HOST=db
POSTGRES_PORT=5432
```

Replace <your-password> with your own password.

Later, we'll pass these values to the PostgreSQL container through Docker Compose. The PostgreSQL image will use them to initialise the database and user.

`POSTGRES_HOST` will contain the PostgreSQL service name (`db`). Docker Compose makes service names available as hostnames to other services on the Compose network.

> [!IMPORTANT]
> Add `.env` to `.gitignore`.

## 9.3. Update `settings.py`

Update the `DATABASES` configuration in `settings.py`:

```py
import os

DEBUG = os.environ.get("DEBUG", "0") == "1"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ["POSTGRES_DB"],
        "USER": os.environ["POSTGRES_USER"],
        "PASSWORD": os.environ["POSTGRES_PASSWORD"],
        "HOST": os.environ.get("POSTGRES_HOST", "localhost"),
        "PORT": os.environ.get("POSTGRES_PORT", "5432"),
    }
}
```

## 9.4. Add the PostgreSQL service

We'll start by adding the basic `db` service to `compose.yaml`:

```yaml
services:
  web:
    # Build the image using `Dockerfile`
    build:
      # use the current directory as the build context
      context: .
      # Build the `development` stage from the `Dockerfile` (not the `production` stage).
      target: development

    # (optional) Name the resulting image.
    image: docker-django

    ports:
      # equivalent to `docker run -p 8000:8000`
      - "8000:8000"

    environment:
      # Set debug mode to true
      - DEBUG=1
      # Database connection settings passed to Django application via environment variables.
      # variables are defined in `.env` and used in `settings.py`
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_HOST=${POSTGRES_HOST}
      - POSTGRES_PORT=${POSTGRES_PORT}

    # start `db` service before `web` service
    depends_on:
      - db

    develop:
      watch:
        # Sync source file changes directly into the container
        # so Django's dev server can reload them without a full image rebuild.
        - action: sync
          path: .
          target: /app
          # don't synchronise changes from these paths.
          ignore:
            - __pycache__/
            - "*.pyc"
            - .git/
            - .venv/
        # Rebuild the image when dependencies change.
        - action: rebuild
          path: pyproject.toml
        - action: rebuild
          path: uv.lock

  db:
    # Run PostgreSQL container using an image
    image: dhi.io/postgres:18
    environment:
      # Left-side names are not arbitrary; Right-side name are defined in `.env`
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
```

Run `docker compose watch` to build and start the development environment again, then verify that both the `db` and `web` containers are running.

## 9.5. Test postgreSQL

1. Run:

```bash
docker compose exec db psql -U postgres -l
```

You should see the `mydockerdjango` database.

2. Run:

   ```bash
   docker compose exec db psql -U postgres mydockerdjango
   ```

   It should connect to the `mydockerdjango` database.

> [!TIP]
> You can also access the `exec` shell from your Docker Desktop by navigating to the `db` container.

## 9.6. Create and run migrations

Run following commands to create and apply migrations:

```bash
docker compose exec web python manage.py makemigrations
docker compose exec web python manage.py migrate
```

## 9.7. Create superuser

Run following command to create a superuser:

```bash
docker compose exec web python manage.py createsuperuser
```

## 9.8. Persist data through volumes

Currently, PostgreSQL stores its data inside the `db` container. If you delete the container, the database data will be lost.

To avoid this, we'll use a Docker volume to store PostgreSQL's data independently of the container.

Update the `compose.yaml` file as follows:

```yaml
services:
  web:
    # ...

  db:
    # Run PostgreSQL container using an image
    image: dhi.io/postgres:18
    volumes:
      # Persist database data across container restarts.
      - db-data:/var/lib/postgresql
    environment:
      # ...

volumes:
  db-data:
```

The `db-data` volume is now managed by Docker and persists even when the `db` container is deleted and recreated.

You can now verify persistence by creating some database data, deleting the `db` container, and recreating it:

```bash
docker compose down
docker compose up -d
```

The database data should still be available because it is stored in the `db-data` volume rather than inside the container.

> [!NOTE]
> docker compose down does not normally remove named volumes. To remove the volume and its data, you would need to explicitly use:
>
> ```bash
> docker compose down -v
> ```

## 9.9. Finalize the compose file

We will now add the following things:

1. `restart: always` - This is appropriate for the `db` service. It tells Docker to automatically restart the PostgreSQL container if it stops.
2. `expose: 5432` - Expose the port only to other services on the Compose network, not to the host machine.
3. `condition: service_healthy`:

   ```yaml
   web:
     depends_on:
       db:
         condition: service_healthy
   ```

   Now Compose doesn't merely start `db` first; it waits until the `db` service passes its healthcheck before starting `web`.

   And in the `db` service:

   ```yaml
   db:
     healthcheck:
       test: ["CMD", "pg_isready"]
       interval: 10s
       timeout: 5s
       retries: 5
   ```

   `pg_isready` checks whether PostgreSQL is accepting connections.

So, the final `compose.yaml` file is:

```yaml
services:
  web:
    # Build the image using `Dockerfile`
    build:
      # use the current directory as the build context
      context: .
      # Build the `development` stage from the `Dockerfile` (not the `production` stage).
      target: development

    # (optional) Name the resulting image.
    image: docker-django

    ports:
      # equivalent to `docker run -p 8000:8000`
      - "8000:8000"

    environment:
      # Set debug mode to true
      - DEBUG=1
      # Database connection settings passed to Django application via environment variables.
      # variables are defined in `.env` and used in `settings.py`
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_HOST=${POSTGRES_HOST}
      - POSTGRES_PORT=${POSTGRES_PORT}

    # Wait for the database to pass its healthcheck and
    # start the `db` service before starting the `web` service.
    depends_on:
      db:
        condition: service_healthy

    develop:
      watch:
        # Sync source file changes directly into the container
        # so Django's dev server can reload them without a full image rebuild.
        - action: sync
          path: .
          target: /app
          # don't synchronise changes from these paths.
          ignore:
            - __pycache__/
            - "*.pyc"
            - .git/
            - .venv/
        # Rebuild the image when dependencies change.
        - action: rebuild
          path: pyproject.toml
        - action: rebuild
          path: uv.lock

  db:
    # Run PostgreSQL container using an image
    image: dhi.io/postgres:18
    # Automatically restart the db container if it stops.
    restart: always
    volumes:
      # Persist database data across container restarts.
      - db-data:/var/lib/postgresql
    environment:
      # Left-side names are not arbitrary; Right-side name are defined in `.env`
      # These are PostgreSQL image environment variables.
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    # Expose the port only to other services on the Compose network,
    # not to the host machine.
    expose:
      - 5432
    # Only report healthy once PostgreSQL is ready to accept connections,
    # so the web service doesn't start before the database is available.
    healthcheck:
      test: ["CMD", "pg_isready"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  db-data:
```

## 9.10. Final test

Run the follwowing commands once again:

```bash
docker compose down
docker compose up --build
```

Check that everything is okay.
