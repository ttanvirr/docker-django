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
