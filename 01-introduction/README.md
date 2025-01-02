# Mastering Nginx - Introduction

Welcome to this introductory guide on Nginx! This README summarizes the key points covered in the **"Introduction to Nginx"** video, giving you an overview of its features, uses, and installation process. Whether you're a developer, system administrator, or just curious, this guide is for you. Let’s dive in!

---

## What is Nginx?
Nginx (pronounced "Engine X") is a powerful open-source software primarily used as a web server. But its versatility extends much further. Nginx can also function as:  
- **Reverse Proxy**: Distributes requests to backend servers.  
- **Load Balancer**: Efficiently manages traffic across multiple servers.  
- **Content Caching System**: Improves performance by serving cached resources.  
- **Media Streaming Server**: Seamlessly delivers audio and video content.  

### Key Features:
- High performance and low resource usage.  
- Handles massive numbers of simultaneous connections.  
- Originally created by Igor Sysoev in 2004 to solve the "C10k problem" (handling 10,000 simultaneous connections efficiently).  

![Nginx Architecture](https://via.placeholder.com/800x400 "Diagram of Nginx Architecture")

---

## Why Choose Nginx?
Nginx is widely popular for its:

1. **Scalability**: Its event-driven architecture handles thousands of connections simultaneously.  
2. **Versatility**: Functions as a web server, reverse proxy, load balancer, and more.  
3. **Performance**: Outperforms traditional web servers like Apache for static content and high-traffic handling.  
4. **Widespread Adoption**: Trusted by industry giants like Netflix, Airbnb, and WordPress.com.  

---

## Differences Between Nginx and Apache
While both Nginx and Apache are powerful web servers, they differ in several ways:  

| Feature             | Nginx                  | Apache                 |
|---------------------|------------------------|------------------------|
| **Architecture**    | Event-driven           | Process-driven         |
| **Static Content**  | Faster serving         | Slower serving         |
| **Configurations**  | Centralized in one file | Distributed with `.htaccess` files |

*Nginx is often preferred for modern, high-performance applications.*

---

## Installing Nginx
Here's how to install Nginx on various platforms:  

### Ubuntu:
```bash
sudo apt update  
sudo apt install nginx  
```

### CentOS:
```bash
sudo yum install nginx  
```

### macOS (via Homebrew):
```bash
brew install nginx  
```

### Edit your Nginx file
```bash
File In MAc will be at 
sudo vim /opt/homebrew/etc/nginx/nginx.conf
```

You can chnage port.

Then relaod nginx and restrt using these comamnds

```bash
nginx -t
nginx -s reload
brew services restart nginx
```

### Start Nginx:
```bash
sudo systemctl start nginx  #On Ubuntu

brew services start nginx #on mac

```

### Stop Nginx:
```bash
sudo systemctl stop nginx  #On Ubuntu

brew services stop nginx #on mac
```

After installation, visit `http://localhost:8000` in your browser to see the default Nginx welcome page! port will be in your nginx file. 

---

## Closing Thoughts
In this introduction, we covered:  
- What Nginx is and its key features.  
- Why Nginx is a popular choice for modern applications.  
- How to install Nginx on different platforms.  

In the next section, we’ll dive deeper into Nginx configurations to customize it for your needs. Stay tuned!  

---

### Feedback
If you have questions or feedback, feel free to reach out. Let’s master Nginx together!
