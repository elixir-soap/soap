FROM php:8.4-cli
RUN apt-get update && apt-get install -y --no-install-recommends libxml2-dev curl && docker-php-ext-install soap
COPY . /app
WORKDIR /app
CMD ["php", "-S", "0.0.0.0:8080", "router.php"]
