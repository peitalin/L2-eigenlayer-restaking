module.exports = {
  apps: [{
    name: "app-server",
    script: "tsx",
    args: "src/server.ts",
    env: {
      USE_SSL: "true",
      NODE_ENV: "production"
    },
    watch: false,
    max_memory_restart: "1G",
    exec_mode: "fork",
    instances: 1,
    autorestart: true,
    restart_delay: 3000,
    log_date_format: "YYYY-MM-DD HH:mm:ss Z",
    merge_logs: true
  }]
};