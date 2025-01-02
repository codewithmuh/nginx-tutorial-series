
# Nginx Basics

This guide provides an introduction to Nginx basics, covering configuration structure, key directives, and service management. It is designed to help beginners develop a solid foundation for working with Nginx.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Configuration File Structure](#configuration-file-structure)
3. [Key Directives](#key-directives)
4. [Starting and Managing Nginx](#starting-and-managing-nginx)
5. [Next Steps](#next-steps)
6. [Resources](#resources)

---

## Introduction

Nginx is a powerful web server and reverse proxy used widely for web application delivery. This guide will help you:

- Understand the Nginx configuration structure.
- Learn key directives for setting up Nginx.
- Manage the Nginx service confidently.

---

## Configuration File Structure

The main configuration file for Nginx is `nginx.conf`, typically located in `/etc/nginx/`. It is structured into hierarchical contexts:

1. **Main Context**: Contains global settings (e.g., `worker_processes`).
2. **HTTP Context**: Defines behavior for HTTP traffic, such as caching and server blocks.
3. **Server Blocks**: Handles domain or application-specific configurations.

### Example Configuration
```nginx
worker_processes  1;  # Main context  

http {  
    server {        # Server block  
        listen 80;  
        server_name example.com;  
        root /var/www/html;  # Document root  
        index index.html;    # Default index file  
    }  
}
```
This example:

- Listens on port 80.
- Serves files from `/var/www/html`.
- Uses `index.html` as the default file.

---

## Key Directives

Here are some essential directives to know:

- **listen**: Specifies the port or IP address for Nginx to listen on.
    ```nginx
    listen 80;  # HTTP  
    listen 443 ssl;  # HTTPS  
    ```

- **server_name**: Defines the domain name for the server block.
    ```nginx
    server_name example.com www.example.com;  
    ```

- **root and index**: Sets the document root and default file.
    ```nginx
    root /var/www/html;  
    index index.html index.htm;  
    ```

- **location**: Configures how specific requests are handled.
    ```nginx
    location /images/ {  
        root /var/www/media;  
    }
    ```

These directives form the backbone of any Nginx configuration.

---

## Starting and Managing Nginx

### Common Commands

- **Start Nginx**:
    ```bash
    sudo systemctl start nginx
    ```

- **Stop Nginx**:
    ```bash
    sudo systemctl stop nginx
    ```

- **Reload Configuration**:
    ```bash
    sudo systemctl reload nginx
    ```

- **Test Configuration**:
    ```bash
    sudo nginx -t
    ```
    Always test your configuration to ensure there are no syntax errors before reloading.

---

## Next Steps

With a solid understanding of the basics, you're ready to move on to more advanced topics. Next, consider learning about:

- Hosting a static website with Nginx.
- Setting up HTTPS with SSL/TLS.
- Using Nginx as a reverse proxy for backend services.

---

## Resources

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Static Website Hosting with Nginx](Insert relevant link)
- [YouTube Video: Nginx Basics](Insert your video link)

Enhance your skills further by experimenting with configurations and exploring additional use cases for Nginx.
