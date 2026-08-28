# Table of Contents <!-- omit in toc -->

- [1. Overview: Containerize a Django application](#1-overview-containerize-a-django-application)
- [2. Prerequisites](#2-prerequisites)
- [3. Create the Django project](#3-create-the-django-project)
- [4. Start with a simple `Dockerfile`](#4-start-with-a-simple-dockerfile)
- [5. Next step](#5-next-step)
  - [5.1. Run the application](#51-run-the-application)

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

# 5. Next step

1. Create a compose.yaml file:

   `compose.yaml`

   ```yml
   services:
     web:
       build: .
       ports:
         - "8000:8000"
   ```

## 5.1. Run the application

From the `django-docker` directory, run:

```bash
docker compose up --build
```

Open a browser and navigate to http://localhost:8000. You should see the Django welcome page.

Press `ctrl+c` to stop the application.
