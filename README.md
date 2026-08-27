# Table of Contents <!-- omit in toc -->

- [1. Overview: Containerize a Django application](#1-overview-containerize-a-django-application)
- [2. Prerequisites](#2-prerequisites)
- [3. Create the Django project](#3-create-the-django-project)
- [4. Create a production `Dockerfile`](#4-create-a-production-dockerfile)
  - [Run the application](#run-the-application)

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

# 4. Create a production `Dockerfile`

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

4. Create a `Dockerfile` with the following contents:

   ```dockerfile
    # syntax=docker/dockerfile:1

    # Build stage: the -dev image includes tools needed to install packages.
    FROM dhi.io/python:3.14-alpine3.23-dev AS builder

    # Prevent Python from writing .pyc files to disk.
    ENV PYTHONDONTWRITEBYTECODE=1
    # Prevent Python from buffering stdout/stderr so logs appear immediately.
    ENV PYTHONUNBUFFERED=1

    RUN pip install --quiet --root-user-action=ignore uv
    # Use copy mode since the cache and build filesystem are on different volumes.
    ENV UV_LINK_MODE=copy

    WORKDIR /app

    # Install dependencies into a virtual environment using cache and bind mounts
    # so neither uv nor the lock files need to be copied into the image.
    RUN --mount=type=cache,target=/root/.cache/uv \
        --mount=type=bind,source=uv.lock,target=uv.lock \
        --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
        uv sync --frozen --no-install-project

    # Runtime stage: minimal DHI image with no shell or package manager,
    # already runs as the nonroot user.
    FROM dhi.io/python:3.14-alpine3.23

    # Prevent Python from buffering stdout/stderr so logs appear immediately.
    ENV PYTHONUNBUFFERED=1
    # Activate the virtual environment copied from the build stage.
    ENV PATH="/app/.venv/bin:$PATH"

    WORKDIR /app

    # Copy the pre-built virtual environment and application source code.
    COPY --from=builder /app/.venv /app/.venv
    COPY . .

    EXPOSE 8000

    # Run Gunicorn as the production WSGI server.
    CMD ["gunicorn", "myapp.wsgi:application", "--bind", "0.0.0.0:8000"]
   ```

5. Create a compose.yaml file:

   `compose.yaml`

   ```yml
   services:
     web:
       build: .
       ports:
         - "8000:8000"
   ```

## Run the application

From the `django-docker` directory, run:

```bash
docker compose up --build
```

Open a browser and navigate to http://localhost:8000. You should see the Django welcome page.

Press `ctrl+c` to stop the application.
