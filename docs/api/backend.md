# PetIntelli 后端 API 文档

> version: 1.0 · date: 2026-06-16 · 适用:petintelli-backend(FastAPI,小程序上线版)
> 在线交互文档:`GET /docs`(Swagger UI)· 机读:`GET /openapi.json`
> 字段级详细契约见仓库根 `API_CONTRACT_PetIntelli.md`;本文件是落地速查。

---

## 0. 全局约定

- **Base URL**:`http(s)://<服务器地址>:<端口>`(部署时由网关/反代决定;容器内 8000)。小程序 `config.js` 的 base 指到这里。
- **响应信封**:所有响应统一 `{ "code": <HTTP码>, "message": <文案>, "data": <负载> }`。前端在 `code==200||201` 时只取 `data`;`code==401` 触发重新登录。
- **鉴权**:除标「公开」的接口外,请求头都要带 `Authorization: Bearer <access_token>`(登录拿到的整串)。
- **ID 一律字符串**:所有 `id`/`petId`/`userId`/`bindingId` 等都是 `str`(后端 `str()` 过),前端用 `String()` 比较,**禁 `Number()`**(可能精度丢失)。
- **分页**:`{ "total": int, "list": [...] }`,`index` 页码从 0 起。
- **枚举对外用 int 码**:`species` 1=狗/2=猫/3=其他;`gender` 0=未知/1=公/2=母;`notice.type` 0=系统/1=健康/2=定位;`notice.status` "0"=未读/"1"=已读。
- **时间格式**:`birthday` = `"YYYY-MM-DD"`;一般时间戳 = `"YYYY-MM-DD HH:MM:SS"`。
- **通用错误**:401(未登录/失效)· 403(越权)· 404(不存在)· 400(入参错,文案在 `message`)· 409(状态冲突,如设备已被绑)。

---

## 1. 系统探针(公开,无需鉴权)

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 存活探针。返回 `{"status":"ok"}`(不连库)。 |
| GET | `/readyz` | 就绪探针。**连上真库才返回 `{"status":"ready"}`**——验证后端↔数据库通不通看这条。 |

---

## 2. 认证 / 用户

### `GET /auth/code/get?mobile=`(公开)
发送短信验证码。query `mobile`(11 位手机号)。返回 `message="验证码已发送"`,无 data。

### `POST /auth/register`(公开)
注册并自动登录。body:`{ "mobile", "password", "code" }`(三者必填)。
返回 data:`{ "id", "access_token", "refresh_token", "token_type":"Bearer", "expires_in" }`。
错误:400「手机号已注册」/「验证码错误或已过期」/「手机号格式不正确」。

### `POST /auth/login`(公开)
登录。body:`{ "mobile", "password" }` 或 `{ "mobile", "code" }`(密码、验证码二选一)。
返回 data 同 register。错误:400「该手机号未注册」/「密码错误」/「验证码错误或已过期」。

### `GET /auth/users/me`
取当前用户资料。返回 data:
`{ "id", "name", "avatar"(签名URL|null), "gender"(int|null), "birthday"("YYYY-MM-DD"|null), "location"(string[]|null), "description"(string|null), "isLost"(bool), "lostText"(string|null) }`。

### `PUT /auth/users/me` · `PUT /users/{id}`
更新资料(前端主路径是 `PUT /users/{id}`)。body:`{ "name"(必填), "gender"(只收1/2), "birthday", "location"(长度2), "description", "lostText", "avatar"(OSS key), "isLost" }`。返回 `message="用户信息更新成功"`。

---

## 3. 宠物(均需鉴权;owner 由 token 推断)

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/pets` | 我的宠物列表。返回 data = **裸数组** `[PetSummary]`(无宠物→`[]`)。 |
| POST | `/pets` | 新建宠物。201。 |
| GET | `/pets/{petId}` | 宠物详情(非本人→404 防探测)。 |
| PUT | `/pets/{petId}` | 全量更新(缺字段=不改)。 |
| PATCH | `/pets/{petId}` | 部分更新。 |
| DELETE | `/pets/{petId}` | 软删 + 级联解绑其设备。 |

**PetSummary / PetDetail 字段**(出参,枚举恒 int):
`{ "id", "collarId"(派生绑定nfc,无→""), "name", "age"(int|null,birthday派生), "avatarId", "avatar", "species"(1/2/3), "gender"(0/1/2), "variety", "birthday", "weight"(number), "isSterilized"(bool) }`

**POST/PUT 入参**:`name`(必填)、`species`/`gender`(int 或数字串)、`variety`、`birthday`、`weight`、`isSterilized`、`avatarId`、`avatar`(OSS key)、`petCode`(可选,不传自动生成)。
错误:400「宠物名称必填」/「该宠物编号已存在」/「性别字段不合法」/「物种字段不合法」/「日期格式应为 YYYY-MM-DD」;403「无权操作该宠物」;404「宠物不存在」。

---

## 4. 设备绑定(预置+匹配;均需鉴权)

> 铁律:设备须产线预置进库;扫码只匹配,**未入库的 UID 一律 404**,绝不凭空创建。字段 snake_case(本域约定)。

### `GET /hardware/nfc/{nfc_uid}/binding`
绑定前查重(恒 200)。
- 未绑定:`{ "nfc_uid", "bound": false }`
- 自己的设备:`{ "nfc_uid", "bound": true, "user_id", "pet_id", "binding_id", "lost_mode", "lost_contact", "current_module": {...}|null }`
- 他人的设备(脱敏):`{ "nfc_uid", "bound": true }`

### `POST /hardware/nfc/bind`
绑定。body:`{ "nfc_uid"(必填), "pet_id"(可选,须属当前用户) }`。201,返回 `{ "message":"绑定成功", "binding_id", "nfc_uid", "user_id", "pet_id" }`。
错误:404「设备未入库或不存在」;409「该设备已被其他用户绑定」/「该设备已绑定其他宠物」/「该设备状态异常,无法绑定」;403「无权操作该宠物」。

### `POST /hardware/nfc/{nfc_uid}/unbind`
解绑(本人或宠物属主)。返回 `message="解绑成功"`(无 active 绑定时幂等返回「设备已解绑」)。错误:404「设备未入库或不存在」;403「无权操作该设备」。

---

## 5. 首页

### `GET /home/{petId}`
首页今日状态摘要(读 serving 快照)。返回 data 含:`messageCount`(未读告警数)、`status`(状态文案)、`desc`(标签数组)、`movingTarget`、`foodIntakeRecord`、`sleepDuration`、`heartRateList`/`respiratoryRateList`/`steps`/`emotional` 等聚合指标。无数据时为最小兜底 `{ "id" }`。错误:404「宠物不存在」;403「无权操作该宠物」。

---

## 6. 健康

### `GET /health/{petId}`
健康概况(读 serving 快照)。返回 data 含生理体征(`heartRate`/`respiratoryRate`/`stressIndex`/`hrv`…)、趋势、`healthEvidence`(风险证据块)等。无快照→`{}`。错误:404「宠物不存在」;403「无权访问该宠物」。

### `GET /pets/{petId}/archive/healthRecords`
手动健康记录列表。返回 data = 裸数组 `[{ "id", "time"("YYYY-MM-DD HH:MM:SS"), "des" }]`。

### `POST /pets/{petId}/archive/healthRecords`
新增手动记录。body:`{ "time"("YYYY-MM-DD HH:MM:SS"), "des" }`(必填)。返回 `message="健康记录添加成功"`。错误:400「time 和 des 必填」/「时间格式错误,应为 YYYY-MM-DD HH:MM:SS」。

---

## 7. 消息中心

### `GET /home/message/notice?type=&index=&size=`
通知列表(分页)。query:`type`(-1全部/0系统/1健康/2定位,默认-1)、`index`(页码默认0)、`size`(每页默认10)。
返回 data:`{ "total", "list": [{ "id", "petId", "title", "desc", "route", "status"("0"/"1"), "type"("0"/"1"/"2"), "icon", "date" }] }`。

### `POST /home/message/notice`
标单条已读。body:`{ "id" }`。返回 `{}`。错误:404「消息不存在」(重复标记不报错)。

### `POST /home/message/batchNotice`
一键全部已读。无 body。返回 `{}`。

### `DELETE /home/message/notice`
批量删。body:`{ "ids": "12,15,20" }`(逗号分隔)。返回 `{}`。错误:400「缺少 ids 参数」。

---

## 8. 定位 / 轨迹

### `GET /location/{petId}`
定位概览。返回 data(扁平合并):`id`、`distance`(当日里程米)、`sportTotalTime`(分钟)、`location`(简版当前点)、`signalStrength`(0-3)、`mode`(0normal/1emergency/2outing)、`areaList`(安全区)、`device`(在线/电量/状态)、`displayLocation`/`displayLocationRole`/`locationFresh`、`candidateLocation`、`fenceStatus`、`trackingMode` 等。无数据时设备 offline、`location` 为 `{}`。错误:404「宠物不存在」;403「无权操作该宠物」。

### `GET /location/{petId}/routes?index=&size=`
历史路线列表(分页,只含汇总)。返回 `{ "total", "list": [{ "id", "startDate", "endDate", "pointCount" }] }`。

### `GET /location/{petId}/routes/{routeId}?maxPoints=`
单条路线点位序列(轨迹回放)。`maxPoints` 默认 500(夹在 2-1000)。返回 data = 裸数组 `[{ "lng", "lat", "date" }]`。错误:404「历史路线不存在」。

### `POST /location/{petId}/mode`
切换追踪模式。body:`{ "mode" }`(int 0/1/2 或 str normal/emergency/outing)。返回 `{ "mode": "normal|emergency|outing" }`。错误:404「未找到有效设备绑定」;400「mode 必须为 0/1/2 或 normal/emergency/outing」。
> 注:本接口只写绑定的模式布尔;下行到设备的真实命令属后续(P4)。

---

## 9. 快速测试

```bash
# 验真库连通(最关键)
curl http://127.0.0.1:8080/readyz                 # {"status":"ready"} = 后端连上 RDS 了

# 走一遍最小闭环(注意取 data 里的 access_token)
curl "http://127.0.0.1:8080/auth/code/get?mobile=13800138000"
curl -X POST http://127.0.0.1:8080/auth/register -H 'Content-Type: application/json' \
     -d '{"mobile":"13800138000","password":"secret123","code":"<验证码>"}'
TOKEN=<上一步 data.access_token>
curl http://127.0.0.1:8080/auth/users/me -H "Authorization: Bearer $TOKEN"
curl -X POST http://127.0.0.1:8080/pets -H "Authorization: Bearer $TOKEN" \
     -H 'Content-Type: application/json' -d '{"name":"旺财","species":1}'
```

> 在线 Swagger UI(能点着测):浏览器开 `http://<服务器>:8080/docs`。

## Changelog
- 2026-06-16 v1.0:首版,覆盖上线 29 个接口(认证/宠物/绑定 + 首页/健康/消息/定位读侧)。
