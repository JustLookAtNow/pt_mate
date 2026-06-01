---
name: deploy-server
description: 将 server 后端新版本构建并部署到服务器；当用户要求更新测试环境或正式环境时使用。测试环境部署到 golakers:~/ptmate-beta 并直接运行；正式环境先停止 ptmate 服务，部署到 golakers:~/ptmate 后再启动 ptmate 服务。
---

# Deploy Server Skill

用于把 `server` 中的新版本更新到远程服务器。

## 环境

- 服务器 SSH 别名：`golakers`
- 构建产物：`server/ptmate-server`
- 测试环境目录：`golakers:~/ptmate-beta`
- 正式环境目录：`golakers:~/ptmate`
- 测试环境访问地址环境变量：`PTMATE_BETA_URL`
- 正式环境访问地址环境变量：`PTMATE_PROD_URL`

真实访问地址必须从本地环境变量读取，不要写入仓库文件，避免提交到 GitHub 后公开。

## 使用流程

1. 判断用户要更新的环境：
   - 用户提到“测试环境”、“beta”、“预发”时，按测试环境流程执行。
   - 用户提到“正式环境”、“生产环境”、“线上”时，按正式环境流程执行。
   - 如果用户没有说明环境，先询问目标环境。
2. 先打包 `server`：

```bash
cd server && ./build.sh
```

3. 确认 `server/ptmate-server` 已生成。

## 测试环境部署

按用户要求，测试环境不使用 `systemctl`，复制到 `~/ptmate-beta` 后进入目录直接运行二进制。默认用 `nohup` 后台启动，并写入 PID 文件，确保部署命令能结束，且后续可以主动停止。

```bash
scp server/ptmate-server golakers:~/ptmate-beta/ptmate-server
ssh golakers 'cd ~/ptmate-beta && chmod +x ptmate-server && nohup ./ptmate-server > ptmate-server.log 2>&1 & echo $! > ptmate-server.pid'
```

如果用户明确要求前台运行，使用：

```bash
ssh golakers 'cd ~/ptmate-beta && chmod +x ptmate-server && ./ptmate-server'
```

### 停止测试环境

因为测试环境默认通过 `nohup` 后台运行，如果不主动停止会一直运行。停止测试环境时优先使用 PID 文件：

```bash
ssh golakers 'cd ~/ptmate-beta && if [ -f ptmate-server.pid ]; then kill "$(cat ptmate-server.pid)" && rm -f ptmate-server.pid; fi'
```

如果 PID 文件不存在或进程已经不是该 PID，使用工作目录筛选兜底，避免误杀正式环境：

```bash
ssh golakers 'cd ~/ptmate-beta && for pid in $(pgrep -f ptmate-server || true); do [ "$(readlink /proc/$pid/cwd 2>/dev/null)" = "$PWD" ] && kill "$pid"; done; rm -f ptmate-server.pid'
```

更新测试环境时，先停止旧进程，再复制和启动新版本：

```bash
ssh golakers 'cd ~/ptmate-beta && if [ -f ptmate-server.pid ]; then kill "$(cat ptmate-server.pid)" 2>/dev/null || true; rm -f ptmate-server.pid; fi; for pid in $(pgrep -f ptmate-server || true); do [ "$(readlink /proc/$pid/cwd 2>/dev/null)" = "$PWD" ] && kill "$pid"; done'
scp server/ptmate-server golakers:~/ptmate-beta/ptmate-server
ssh golakers 'cd ~/ptmate-beta && chmod +x ptmate-server && nohup ./ptmate-server > ptmate-server.log 2>&1 & echo $! > ptmate-server.pid'
```

完成后提示用户可以访问测试环境新版本：

```bash
echo "测试环境新版本已部署，可以访问：${PTMATE_BETA_URL}"
```

## 正式环境部署

正式环境必须先停止 `ptmate` 服务，再复制新产物，最后启动服务。

```bash
ssh golakers 'systemctl stop ptmate'
scp server/ptmate-server golakers:~/ptmate/ptmate-server
ssh golakers 'cd ~/ptmate && chmod +x ptmate-server && systemctl start ptmate'
```

完成后提示用户可以访问正式环境新版本：

```bash
echo "正式环境新版本已部署，可以访问：${PTMATE_PROD_URL}"
```

## 注意事项

- 访问地址只允许通过 `PTMATE_BETA_URL` 和 `PTMATE_PROD_URL` 获取；如果环境变量未设置，先提醒用户设置，不要猜测或补写真实地址。
- 不要在正式环境复制完成前启动服务。
- 如果 `systemctl` 权限不足，按终端报错处理；需要 `sudo` 时先说明将要执行的命令。
- 如果 `scp` 或 `ssh` 失败，保留错误输出并告知用户部署未完成，不要提示“可以访问新版本”。
