# Automated Deployment Shell Script

This is a bash project that automates the process of cloning, Dockerizing, and deploying a web application to a remote Linux server. NGINX was used for a Reverse proxy.

## Core Functionality

  -  Accepts and validates inputs from the user
  -  Clones project repo from the user's GitHub account
  -  Sets up a remote server to handle Dockerization of the project
  -  Build and run Docker containers
  -  Configures NGINX as a reverse proxy
  -  Deploys the application

## Usage/Functional Walkthrough 

  - Have the following things ready:
      -  The repo that holds your project
      -  Your Personal Access Token (PAT) -- Gotten from GitHub
      -  The branch in which the version of the app you want to deploy is held
      -  Your SSH username
      -  Server IP address
      -  SSH key path
      -  App Port
  - On prompt, you'd need to provide the details, and these details are going to be validated
  - After validation, under the hood, the script clones your repo, connects and sets up the remote server, dockerize your app, setup NGINX as reverse proxy and finally deploys it.
  - At every stage, there are basic error handling procedures and logging capabilities. The logs are saved in ./logs
  - To perform a cleanup, you need to pass the --cleanup flag as a parameter to the code:
        `./deploy.sh --cleanup`


@Kadiri Prosper -- HNG 13 (2025)
