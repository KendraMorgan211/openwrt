# 雷神加速器 + dae 共存配置指南

适用环境：OpenWrt 25.12 x86_64（PVE 虚拟机，DHCP 192.168.5.231），
雷神插件 v1.2.1.40（tproxy 模式，端口 5588）已安装，
dae/daed 通过 `openwrt-dae/install-dae.sh` 安装。

---

## 一、共存原理（为什么不用关雷神）

| | 雷神加速器 | dae |
|---|---|---|
| 接管粒度 | **按设备**（APP 里勾选哪些设备走专线） | **按目标地址**（域名/IP 分流） |
| 实现方式 | iptables-legacy TPROXY 规则（空闲时 0 条规则） | eBPF 程序 + 自有 tproxy |
| 监听端口 | 5588 | 12345 |

两者维度不同、规则互补即可共存。Linux netfilter 规则顺序匹配、
一个包只被接管一次，**不会出现 Windows 双开那种死锁**——最坏结果是
某设备只有一个工具生效，不会全网瘫。

## 二、必须遵守的三条规则

### 规则 1：设备分工，不要重叠

- **雷神 APP 只勾游戏设备**（游戏 PC、主机），其他设备不勾；
- dae 配置里把雷神设备的 IP 设为直连，dae 规则示例（`config.dae`）：

```
global {
    # 路由器自身流量不走代理（防止回环）
    tcp_check_url: 'https://www.google.com'
    # 雷神加速的设备：直连，交给雷神专线
    direct: [
        '2a09:b513:2943:ecb3::/64',
        '192.168.5.100/32',   # ← 游戏 PC 的实际 IP
        '192.168.5.101/32',   # ← PS5/Switch 等主机 IP
    ]
}

routing {
    # 游戏平台域名直连（雷神已接管这些设备，双保险）
    domain(upstream: 'direct') {
        # 按需添加
    }
    fallback: proxy
}
```

把上面 IP 换成你实际的设备地址。dae 的 `direct` 是按**目标**匹配的，
源 IP 排除要在 `p2p`/`bind` 之外另行确认——最稳的做法是
**雷神 APP 里不勾的设备，才在 dae 里代理**，从源头不重叠。

### 规则 2：DNS 分工

dae 默认会劫持 DNS 做域名分流。雷神设备的 DNS 请求不能被 dae 拿走：

- LuCI -> 网络 -> DHCP/DNS：确认 dnsmasq 对雷神设备正常解析；
- 若 dae 配置了 `dns { upstream: ... }`，把雷神设备 IP 加入排除，
  或在 dae 的 `dns` 段只用 `request` 模式（劫持路由器自身 DNS，
  不劫持 LAN 设备）——具体取决于你用的 dae 版本语法。

### 规则 3：端口与启动顺序

- 雷神 5588、dae 12345，端口不冲突，无需改动；
- 启动顺序无所谓（规则互补），但**改任何一方配置后重启另一方确认**：
  ```sh
  /etc/init.d/acc restart && /etc/init.d/daed restart
  ```

## 三、验证清单

```sh
# 1. dae 进程与 eBPF 程序加载
ps w | grep dae
bpftool prog show | head -5        # 能看到 dae 的 eBPF 程序即成功

# 2. 雷神空闲时应该 0 条 TPROXY 规则（未开加速时）
iptables -t mangle -S | grep -c TPROXY

# 3. APP 给游戏设备开加速后，雷神规则出现且只匹配该设备
iptables -t mangle -S | grep TPROXY

# 4. dae 分流的设备科学上网正常、雷神设备游戏加速正常
```

## 四、出问题时回退

| 现象 | 处理 |
|---|---|
| dae 启动失败报 BTF 错误 | 固件没带 BTF，检查 `ls /sys/kernel/btf/vmlinux` |
| 游戏加速突然失效 | 检查 dae 是否抢了雷神设备流量，按规则 1 排除 |
| 科学上网不工作 | 看 dae 日志 `logread -e dae`；确认节点订阅有效 |
| 两者都乱 | 先 `stop` dae 保雷神，再慢慢调 `config.dae` |

## 五、已知限制

- **同一设备不能同时享受两种服务**（流量被先接管者整包吃掉）；
- dae 的 eBPF CO-RE 必须内核带 BTF（新固件已解决）；
- 南方电网区域用不了雷神（与本指南无关，仅备忘）。
