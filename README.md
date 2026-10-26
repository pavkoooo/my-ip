# My IP

贴在主显示器右上角、菜单栏正下方的一块小玻璃胶囊。没有 Dock 图标（`LSUIElement`），浮在普通窗口之上，并留在菜单栏下面。

每次启动都显示 **LAN**。地球仪图标在 LAN 和 WAN 之间切换，这个选择只留在内存里，不会记到下次启动。

## 两种地址

- **LAN**（默认）：默认路由所在的 Wi-Fi 或以太网接口的 IPv4。VPN 隧道（例如 `utun`）不算。地址变化时立刻更新（切网、接口上下线、DHCP），另外大约每 20 秒再查一次。
- **WAN**：公网 IPv4。先请求 `https://api.ipify.org`，失败再试 `https://ifconfig.me/ip`，最后试 `https://1.1.1.1/cdn-cgi/trace`。网络路径变化时立刻重取，大约每 25 秒再查一次。

两个地址都会在后台保持更新。切过去时先显示已经缓存的值，再立刻刷新当前这一面。某一面查询失败时，只把那一面显示成短的「—」，不影响另一面。

## 操作

- 点地球仪：在 LAN 和 WAN 之间切换。
- 点地址文字：把当前显示的地址复制到剪贴板，并短暂显示 Copied。
- 右键：菜单里有 Copy IP 和 Quit。
- 鼠标悬停：右侧出现退出按钮。平时不显示。

## 登录时启动

本机用当前用户的 LaunchAgent 启动，不需要管理员权限：

`~/Library/LaunchAgents/com.jilizhe.myipwidget.plist`

`RunAtLoad` 为 true，程序是 `MyIPWidget.app` 里的可执行文件。

## 构建和运行

需要 macOS 12 或更新版本，以及带 `swiftc` 的 Xcode 命令行工具。脚本按本机架构编译，目标是 macOS 12.0，并链接 AppKit、Network 和 SystemConfiguration。

```bash
./build.sh
open MyIPWidget.app
```

`./build.sh` 会在当前目录生成 `MyIPWidget.app`。这个包、构建产物和 `.DS_Store` 不进入版本库。
