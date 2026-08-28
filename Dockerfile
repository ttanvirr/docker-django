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
