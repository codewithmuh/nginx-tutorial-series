
# Hosting Static Websites with Nginx

## Overview

In this guide, you’ll learn how to host a simple static website using Nginx. This is one of the most common use cases for Nginx, and it's a great way to understand server blocks and serving static files. Let's walk through the steps to set up and configure your static site.

---

## Steps

### 1. Opening the Section (1 minute)

**Script:**  
"Now that you're familiar with the basics of Nginx, let's put it into action by hosting a static website. This is one of the simplest and most common use cases for Nginx, and it's a great way to understand server blocks and file serving. Let’s dive in!"

---

### 2. Setting Up Your Files (3 minutes)

**Script:**  
"First, we need some static files to host. For this demo, we’ll create a simple HTML file."

**Commands:**

- Navigate to your document root directory. By default, this is `/var/www/html`:

  ```bash
  cd /var/www/html
  ```

- Create a basic `index.html` file:

  ```bash
  sudo nano index.html
  ```

- Add the following content to the file:

  ```html
  <!DOCTYPE html>
  <html>
    <head><title>Welcome to Nginx</title></head>
    <body><h1>Hello, World! This is Nginx serving a static website.</h1></body>
  </html>
  ```

- Save and exit the file. This will be the homepage for your website.

---

### 3. Configuring the Server Block (5 minutes)

**Script:**  
"Next, let’s configure Nginx to serve this static site."

**Commands:**

- Open the default server block configuration file:

  ```bash
  sudo nano /etc/nginx/sites-available/default
  ```

- Modify the configuration to match the following:

  ```nginx
  server {
      listen 80;
      server_name localhost;  # Or replace with your domain name
      root /var/www/html;
      index index.html;
  }
  ```

- Test the configuration to ensure there are no errors:

  ```bash
  sudo nginx -t
  ```

- Reload Nginx to apply the changes:

  ```bash
  sudo systemctl reload nginx
  ```

Your static website is now live!

---

### 4. Viewing Your Wevsite


To view your website, open a web browser and navigate to `http://localhost` or your server’s IP address. You should see the 'Hello, World!' message we created earlier.

"If you’re using a custom domain, make sure your domain’s DNS points to your server’s IP address. Once that’s set, you can access your site using the domain name."

---


## Summary
"That’s it! You’ve successfully hosted a static website with Nginx. You can now add more HTML, CSS, and JavaScript files to create a complete website. In the next section, we’ll take it a step further by setting up Nginx as a reverse proxy.

In this tutorial, you learned how to host a static website using Nginx. You created a simple HTML file, configured the Nginx server block to serve it, and viewed the website in a browser. You can now continue to expand your website with additional files, or explore other Nginx functionalities.
