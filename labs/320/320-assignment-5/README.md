# Project 5 – Multi-Container Status Dashboard

![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)
![Python](https://img.shields.io/badge/Python-3.10+-yellow?logo=python)
![Flask](https://img.shields.io/badge/Flask-Web%20App-green?logo=flask)
![MariaDB](https://img.shields.io/badge/Database-MariaDB-blue?logo=mariadb)
![Adminer](https://img.shields.io/badge/DB%20Tool-Adminer-lightgrey)
![Portainer](https://img.shields.io/badge/Deployed%20With-Portainer-orange?logo=portainer)
![Status](https://img.shields.io/badge/Build-Class%20Project-success)

This project contains the files you'll use to deploy a **three-container Docker setup**:

* **status-web** – Flask app that reports UP/DOWN health checks
* **app_adminer** – Web interface for managing the database
* **app_db** – MariaDB database container

You will deploy the stack through **Portainer**, update it through **GitHub**, and document your results.

---

## 📁 **Project Structure**

```
docker-compose.yml
status-web/
    app.py
    Dockerfile
    requirements.txt
    templates/
        index.html
```

---

## 🚀 **How to Deploy (Portainer)**

1. Go to **Stacks → Add Stack**
2. Select **Repository**
3. Use your GitHub repo:

```
https://github.com/<your-username>/320-assignment-5.git
```

4. Compose path:

```
docker-compose.yml
```

5. Deploy the stack
6. After updates, use **Pull and redeploy** to refresh the environment

---

## 🌐 **Service URLs**

* **Status-Web:**
  `http://<vm-ip>:8080`

* **Adminer:**
  `http://<vm-ip>:8081`

---

## 🧪 **Health Checks**

The status-web dashboard reports:

* **Status-Web** – app running
* **Adminer** – HTTP check
* **Database** – TCP check on port 3306

UP shows in green; DOWN shows in red.

---

## 🎯 **Your Final Deliverables**

* Working multi-container stack
* Updated health-check dashboard
* Persistence test results
* Debugging test (Adminer DOWN/UP)
* NAT-based external access
* Loop documentation with screenshots
