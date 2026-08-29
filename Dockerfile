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
