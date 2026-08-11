# easy-deploy

让 AI 编程助手（Claude Code / Cursor 等）一句话把你 vibe coding 出来的网站部署上线的 Agent Skill。

部署到**你自己的账号**（Cloudflare / Vercel / Neon），默认走免费额度：不经过任何第三方服务器，没有平台锁定，代码和域名都归你。

## 它能做什么

对 AI 说一句「帮我把这个项目部署上线」，它会：

1. 自动识别项目类型（纯静态 / Vite / Astro / Next.js / 小型 API / 是否需要数据库）
2. 选择合适的免费平台（静态和 SPA → Cloudflare Pages，Next.js → Vercel，小 API → Workers，数据库 → Neon 或 D1）
3. 先在本地构建通过，向你确认部署计划（平台、名称、环境变量、费用）后再执行
4. 部署、配好密钥、用 HTTP 请求验证真的可以访问，最后告诉你线上地址和重新部署的命令

面向国内访问的项目有专门的处理逻辑：会提醒你 `*.vercel.app` 在国内经常打不开、建议绑定自有域名、必要时推荐腾讯 EdgeOne Pages，并如实说明备案的边界（见 `references/china-access.md`）。

## 安装

**Claude Code**（全局，所有项目可用）：

```bash
git clone https://github.com/lttxzmj/easy-deploy ~/.claude/skills/easy-deploy
```

或只装到当前项目：克隆到项目内的 `.claude/skills/easy-deploy/`。

其他支持 Agent Skills（SKILL.md 规范）的工具，把本目录放进对应的 skills 目录即可。

## 使用

在项目目录里对 AI 说：

- 「把这个部署上线」
- 「发布到 Cloudflare，绑我的域名 example.com」
- 「这个项目要给国内用户访问，帮我部署」

前置条件：装好 Node.js；首次部署时 AI 会引导你在浏览器里完成 Cloudflare / Vercel 登录（凭证由官方 CLI 保管，skill 不接触）。

## 目录结构

```
SKILL.md                    # 主流程：探测 → 选平台 → 确认 → 部署 → 验证
scripts/preflight.sh        # 项目类型与工具链探测
references/cloudflare.md    # Pages / Workers / D1 / 自定义域名
references/vercel.md        # Next.js 部署、环境变量、域名
references/databases.md     # Neon / D1 / Supabase 怎么选
references/china-access.md  # 国内可达性、EdgeOne、备案说明
```

## 边界与原则

- 只用你自己的账号，默认免费额度；任何可能产生费用的操作都会先征求同意
- 不碰你没要求改的 DNS；密钥只写入平台 secret，绝不提交到 git
- 长驻服务（WebSocket、Docker、后台任务）不在核心范围内，AI 会说明并和你确认方案（Fly.io / Railway）
- 国内节点加速需要 ICP 备案，本 skill 不代办，只如实告知选项

## License

MIT
