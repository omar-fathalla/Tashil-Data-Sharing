# خطة PR #23: البنود 2–5 + قرارات محمد (للمراجعة قبل التنفيذ)
٣ نوفمبر ٢٠٢٦، بتوقيت القاهرة (UTC+2). كل اللي هنا اتعمل read-only: ما اتكتبش حاجة على prod، والـBigQuery والـgcloud اتقروا بس.

## اللي اتنفّذ في الـPR خلاص (مش جزء من الخطة)
- **CI:** الـ3 annotations هما `curly_braces_in_flow_control_structures` في `register_chain_dialog.dart:47` و`:77`، و"exit code 1". اتصلّحوا في commit `c53ce61`.
- **Suggest بقى محصور في نفس السلسلة:** `customers/suggest.go` بقت `Suggest(name, chain, approved)`، و`SuggestionChain(e)` بتحسب سلسلة الاسم المعتمد كده:
  - `Chain` الصريح.
  - لو مفيش، `UploadChain` بعد تطبيق قواعد العميل→السلسلة.
  - لو الاسم seed، قواعد العميل→السلسلة على "fathalla".
  - لو السلسلة فاضية أو مش معروفة، مفيش اقتراح.
  - في `registry.go` بنبعت `ResolveSellInChain(name, uploadChain)`.
  - التست `suggest_chain_test.go`: «QA فتح الله جملة (طنطا)» ما بيتقترحش أبداً على رفع زهران، والعكس صحيح، ونفس السلسلة لسه بتاخد اقتراح.
  - إصلاح التسمية «فرع … - » ما اتلمسش.
- **ITEM7_84.csv** جاهز (التفاصيل تحت).

---

## بند 2: الأمان (X-Simulated-Role / X-Assigned-*) + قرار حذف الـ`admin` القديم

### السبب
`middleware/auth.go`:
- `:150` بياخد `verified := *claims` قبل أي تعديل. ده كويس.
- `:160-166` `X-Simulated-Role`: الشرط `role != super_admin || allowDemo || claims.Role == super_admin`، فأي مستخدم logged-in يقدر ياخد أي role غير super_admin.
- `:167-172` `X-Assigned-Chain` / `X-Assigned-Region` بيكتبوا فوق `AssignedChain` / `AssignedRegion` من غير أي شرط.
- `:175` الـcontext بيشيل `claims` المعدّلة تحت `UserClaimsContextKey`، والأصلية تحت `VerifiedClaimsContextKey`.

### سلسلة customer decide (approve/reject/unmerge): **بتستخدم الـrole المعدّل من الهيدر. مؤكَّد.**
1. `cmd/server/main.go:287-289` بيوجّه `POST /api/v1/customers/registry/{approve,reject,unmerge}` لـ`HandleApprove/Reject/Unmerge`.
2. `handlers/customer_registry_handler.go:66` (`HandleApprove`) بيروح لـ`:81` `decide(...)`.
3. `:82` `c, ok := tmClaims(w, r)`.
4. `handlers/trade_marketing_handler.go:55-56` `tmClaims` بتنادي `middleware.GetUserClaims` (claims المعدّلة).
5. `customer_registry_handler.go:86` `if !dataQualityWriteRoles[c.Role]`.
6. `handlers/data_quality_handler.go:33-36` `dataQualityWriteRoles` = super_admin, vendor_admin, admin, national_sales_manager, executive.

النتيجة: merchandiser يبعت `X-Simulated-Role: vendor_admin`، فيعدّي ويوافق على عميل. الموافقة بتشغّل reapply، وده بيكتب Sell-In.

### ثغرة أخطر لقيتها: `checkSuperAdminAccess`
`handlers/admin_handler.go:92-94`: لو `X-Simulated-Role` = `super_admin` بيرجع `true` على طول، قبل ما يبص على الـtoken أصلاً. يعني **أي مستخدم logged-in يقدر** يعمل create/update/delete tenant ويعمل reset لباسورد tenant (`:418`, `:620`, `:696`, `:547`) بمجرد هيدر.

### كل write handler ومصدر الـrole النهارده
| Route | Handler (file:line) | البوابة | مصدر الـclaims |
|---|---|---|---|
| POST/PUT/DELETE admin/tenants, reset-password | admin_handler.go:418/620/696/547 | `checkSuperAdminAccess` | **الهيدر مباشرة**، وبعدين GetUserClaims |
| POST admin/chains | admin_handler.go:182 | `chainWriteAccess` | GetVerifiedClaims ✅ (بس لسه بيقبل `admin`) |
| PUT/DELETE admin/chains/{id} | admin_handler.go:280/349 | `chainWriteAccess` | GetVerifiedClaims ✅ (نفس الكلام) |
| POST ingest/upload (+dry_run) | upload_handler.go:373 | `EnforceTenantRLS` بس، **مفيش role** | GetUserClaims (tenant بس) |
| POST ingest/commit | upload_handler.go:492 | مفيش role | GetUserClaims |
| POST ingest/discard | upload_handler.go:553 | مفيش role | GetUserClaims |
| POST/DELETE ingest/clear (فيها `scope=all`!) | upload_handler.go:37 | **مفيش role** | GetUserClaims |
| POST ingest/load-default-excel, load-sell-in-plan | upload_handler.go:298 / :73 | مفيش role | GetUserClaims |
| DELETE ingest/archive | upload_handler.go:728 | مفيش role | GetUserClaims |
| PUT/POST product-master/item | analytics_handler.go:636 | مفيش role | GetUserClaims |
| POST product-master/upload | upload_handler.go:204 | مفيش role | GetUserClaims |
| PUT product-master/chain-discounts | chain_discount_handler.go:65 | `chainDiscountWriteRoles[c.Role]` | tmClaims، يعني **المعدّلة** |
| POST/DELETE analytics/targets، targets/upload | targets_and_sellin_handler.go:121 / :206 | مفيش role | GetUserClaims |
| PATCH data-quality/issues/{id} | data_quality_handler.go:84 | `dataQualityWriteRoles` | tmClaims، **المعدّلة** |
| POST customers/registry/approve/reject/unmerge (+reapply) | customer_registry_handler.go:66→81 | `dataQualityWriteRoles` | tmClaims، **المعدّلة** |
| POST/PUT/DELETE trade-marketing/expenses، upload | trade_marketing_handler.go:127/132/209، trade_marketing_roi.go:250 | `tmWriteRoles` | tmClaims، **المعدّلة** |
| POST/DELETE competitors/custom-skus | competitor_handler.go:103/161 | `tmWriteRoles` | tmClaims، **المعدّلة** |
| POST audit/logs | audit_handler.go:100 | مفيش role | GetUserClaims |
| POST auth/change-password | auth_handler.go:241 | المستخدم نفسه | GetUserClaims (بس الـUserID مش بيتغير بالهيدر) |

قراءات الـKAM بتفلتر بـ`claims.AssignedChain`، فالهيدر بيكسرها: `analytics_handler.go:62`، `targets_and_sellin_handler.go:75`، `sellin_monthly_handler.go:42`، `trade_marketing_handler.go:64-66` (`kamChain`).

### التغيير المقترح (جوه PR #23، حسب قرار محمد)
1. **`auth.go:160-173`:** الهيدرز التلاتة يتطبّقوا بس لو `verified.Role == super_admin` أو `a.allowDemoTokens`. غير كده يتجاهلوا (ومن غير error، عشان الـUI الحالي).
2. **`checkSuperAdminAccess`:** يتشال سطر الهيدر (`:93-95`)، ويبقى `GetVerifiedClaims().Role == super_admin`. حالة `TenantID=="system"` تفضل على الـverified.
3. **helper جديد** `middleware.WriteClaims(r)` بيرجّع الـverified claims، والـtenant = الـverified tenant. استثناء: super_admin بيقدر يعمل switch بـX-Tenant-ID (ده السلوك الحالي، وده بيضيّق ومش بيوسّع).
   - `tmClaims` يفضل للقراءة.
   - نضيف `tmWriteClaims` وتستخدمه كل الـwrite handlers اللي في الجدول اللي فيها role: decide (approve/reject/unmerge)، data-quality patch، chain-discounts، trade-marketing، competitors.
4. **upload/commit/discard/dry-run/reapply/clear/archive delete/targets/product-master:** نضيف بوابة role من الـverified claims (`ingestWriteRoles`).
   - **محتاج قرار محمد في الأدوار.** اقتراحي: super_admin + vendor_admin + national_sales_manager.
   - `ingest/clear?scope=all` يبقى super_admin بس.
5. **قرار محمد 1:** `chainWriteAccess` (admin_handler.go ~:50) يقبل vendor_admin + super_admin بس، ونشيل `domain.RoleAdmin`. وفي Flutter `canManageChains` يتشال منها `admin`.
   - **سؤال:** هل نشيل `admin` كمان من `dataQualityWriteRoles` و`tmWriteRoles`؟ قرار محمد كان على تسجيل السلاسل بس، فمش هلمسهم من غير موافقة.

### التستات
- `middleware/auth_test.go`:
  - merchandiser + `X-Simulated-Role: vendor_admin`: الـrole في الـcontext يفضل merchandiser.
  - super_admin + نفس الهيدر: يتطبّق.
  - `allowDemoTokens=true`: يتطبّق.
  - chain_kam(A) + `X-Assigned-Chain: B`: AssignedChain يفضل A.
- `handlers`:
  - non-admin + `X-Simulated-Role: vendor_admin`: **403** على approve/reject/unmerge، وعلى POST/PUT/DELETE admin/chains.
  - `X-Simulated-Role: super_admin` من مستخدم عادي: 403 على admin/tenants.
  - `admin` القديم: 403 على chain writes.
  - vendor_admin: 201.
- **قراءة chain-A بهيدر B:** نستخدم fixture فيه صفوف A و B، والـKAM(A) يبعت `X-Assigned-Chain: B` على sell-in monthly وanalytics وtargets. لازم يرجع **صفر صفوف من B** (صفوف A بس).
- Flutter: الـUI لسه بيبعت الهيدرز في role switcher؛ هيشتغل عادي لـsuper_admin، والباقي هيتجاهل.

### خطر البيانات
مفيش تغيير في بيانات. الخطر وظيفي:
- أي شاشة غير super_admin كانت بتعتمد على role مُحاكى هتشوف صلاحياتها الحقيقية.
- لو فيه مستخدم حقيقي دوره مش في `ingestWriteRoles`، هيفقد الرفع. لازم نراجع قايمة المستخدمين read-only قبل التنفيذ.

---

## بند 3: ALLOW_DEMO_TOKENS على prod
- `gcloud run services describe tashil-backend --region=europe-west1 --project=tashil-data-sharing`، revision `tashil-backend-00057-lx5`.
- اتقرا المتغير ده بس: **`ALLOW_DEMO_TOKENS=false`** ✅.
- **لو كان true** (auth.go:75-140):
  - tokens زي `demo-superadmin-token` و`superadmin-jwt` بتدّي super_admin.
  - `demo-adeco-token` و`demo-<slug>-token` بتدّي vendor_admin على `tenant-<slug>`.
  - **الطلب اللي مفيهوش token خالص** بياخد vendor_admin على الـtenant اللي في `X-Tenant-ID`.
  - كمان شرط الهيدرز (بعد التعديل) هيسمح بالمحاكاة.
  - يعني أي حد على الإنترنت يبقى admin.
- **مقترح:** تست يتأكد إن القيمة الافتراضية false، وتحذير log عند الـstartup لو `ENVIRONMENT=production` و`ALLOW_DEMO_TOKENS=true`. والأحسن نرفض نشتغل في الحالة دي.

---

## بند 4: قاعدة الـprefix (qa_test: qa_ → qat_)
**السبب:** `gemini/wide_matrix_parser.go` `BuildBranchStoreMetadata`:
- قبل: `chain[:3]` أياً كان.
- دلوقتي: `storeIDPrefixForChain` (:1777). أي سلسلة أول 3 حروف فيها `_` أو `-` أو غير ascii-lowercase بيتغير الـprefix بتاعها، أو بيرجع "" فيرجع للـdefault.

**BigQuery (read-only):**
- `sell_out_facts` هو الجدول الوحيد اللي فيه `store_id`. `sell_in_records` مفيهوش store_id، فيه `customer_branch_code`، والـparser ده ما بيلمسوش.

| tenant | chain_key | store_id prefix | صفوف | stores | batches |
|---|---|---|---|---|---|
| tenant-adeco | fathalla | `fat_` | 58,658 | 34 | 2 |
| tenant-adeco | qa_test | `gom_` (`gom_auto_c460aa08`، من `15_sellout_form_vs_sheet.xlsx`) | 2 | 1 | 1 |

- **مفيش ولا store_id موجود بيبدأ بـ`qa_`** أو بأي prefix فيه `_` / `-`. التغيير ما بيأثرش على أي صف موجود.
- سلاسل prod المعروفة: الـ`SELLIN_CUSTOMER_CHAIN_MAP` = gomla, chain-1080314, zahran، والقواعد الداخلية beet-elgomla و fathalla. قيمتها القديمة والجديدة:
  - `gomla` → `gom` (case صريح، ما اتغيرش)
  - `beet-elgomla` → `bet` (case صريح)
  - `fathalla` → `fat`
  - `zahran` → `zah` (نفسه)
  - `chain-1080314` → `cha` (نفسه)
  - `qa_test` → **`qat`** (كان `qa_`)
- **مقترح التجميد** (`frozenStoreIDPrefixes`): خريطة صريحة chain→prefix للسلاسل الموجودة، فيها `qa_test: "qa_"` حسب طلب محمد، وكل السلاسل اللي فوق.
  - `storeIDPrefixForChain` تبص في الخريطة الأول، وبعدين القاعدة الجديدة للسلاسل الجديدة بس.
  - الكود العربي أو أقل من 3 حروف alnum يرجع للـdefault (`store_<chain>`) زي ما هو.
- **التستات:**
  - `store_prefix_freeze_test.go` يتوسع: لكل سلسلة في الخريطة الـprefix = القيمة القديمة (`qa_test` → `qa_`).
  - سلسلة جديدة `el-wakala` → `elw`.
  - parity الـStoreID على fixtures لكل سلسلة.
- **محتاج نتأكد قبل التنفيذ:** قايمة السلاسل المسجلة في Firestore `tenant_retail_chains`، read-only. ما قرأتهاش المرة دي؛ هنضيف أي code فيه `_` أو `-` للخريطة.
- **خطر البيانات:** صفر على الصفوف الموجودة. الخطر بس على رفع qa_test جديد لو ما اتجمّدش.

---

## بند 5: store_unassigned_main بدل gom_*
**التغيير:** في `tabular_parser.go:1167` و`resolveCanonicalStoreID` (~:1990) و`defaultStoreNameForRetailer`، الـretailer الفاضي ما بقاش gomla.
- النتيجة: `store_unassigned_main` / «فرع غير محدد».
- case "gomla" الصريح لسه بيدّي `gom_cairo_nasrcity` إلخ زي ما هو.

**التأكيد (read-only):**
- **BigQuery:** كل الـ`gom_*` في `sell_out_facts` = **صفين بس** (store `gom_auto_c460aa08`، chain_key=qa_test، ملف تست 15). ده بالظبط الـbug اللي بنصلّحه. مفيش ولا صف `gom_*` تحت chain gomla، ومفيش sell-in store ids.
- **Mapping:** `SELLIN_CUSTOMER_CHAIN_MAP` على prod (`كيه اتش=gomla;المنصوره=chain-1080314;زهران=zahran`) مبني على اسم العميل في Sell-In، مش على store_id، فالتغيير ما بيلمسوش.
  - الـ60 اسم «كيه اتش» اللي في ITEM7 بيروحوا gomla بالقاعدة دي، ومش متأثرين.
- **الكود:** `gom_` بيتولد بس من case "gomla" الصريح ومن `BuildBranchStoreMetadata("gomla", …)`. والاتنين ما اتغيروش.
- **Parity:** in25/in26/Clean متطابقين مع main (rows/value/digests).
- **التستات:**
  - صف من غير retailer → `store_unassigned_main`.
  - retailer=gomla → `gom_cairo_nasrcity` زي ما هو.
  - قايمة الـstore ids الموجودة (fixture) ما تتغيرش.
- **خطر البيانات:** الصفين `gom_auto_c460aa08` بتوع qa_test (تست) هيفضلوا زي ما هما في BigQuery، لأننا ما بنعدّلش صفوف. لو اترفع ملف 15 تاني، هيروح لـstore جديد. ده متوقع ومحصور في qa_test.
  - مش هنمسح حاجة. (تنظيف QA Test ممنوع حسب التعليمات.)

---

## قرار محمد 3: Item 7، الأسماء الـ84 كـalias دائم
**الحقيقة من الداتا:**
- الـ84 كلهم أسماء **seed معتمدة** (`seed_customers.json` فيه 84 اسم بيبدأوا بـ«فرع فتح الله - »).
- الاسم الجديد = القديم من غير «فرع فتح الله - »، بالظبط ومن غير أي استثناء (اتأكدت بـdiff).
- كلهم من **in26.xlsx**. in25 مفيهوش أي فرق.

**التخزين:**
- ملف embedded جديد `customers/seed_aliases.json` شكله `{new_name: old_seed_name}`، متولد بالظبط من ITEM7_84.csv: 84 سطر، اتراجعوا ومحدش خمّنهم.
- مش في Firestore، عشان يبقى ثابت ومتراجع في git. وده نفس منطق الـseed.

**التطبيق:** في `Registry.Partition`، قبل `resolveLocked` (registry.go ~:300):
- لو `seedApplies(tenant)` و`NormalizeName(rec.CustomerName)` موجود في الـaliases، يبقى `rec.CustomerName = old_seed_name`، وبعدين الـresolve العادي يشتغل.
- كده الاسم المخزّن في BQ هو هو، وكل الإجماليات والمجاميع لكل عميل هي هي، ومفيش اسم بيدخل quarantine.
- Exact match بس (normalized)، من غير fuzzy.
- قرار محفوظ في الـregistry (reject/unmerge على الاسم القديم) يفضل يكسب، لأن الـalias بيحوّل للاسم القديم وبعدين `resolveLocked` بيطبّق القرار المخزّن.

**التستات:**
- كل الـ84 اسم جديد يتحلّوا لـapproved. `Partition` يرجّع `q` فاضي.
- **Parity على in26** (opt-in `TDS_CLIENT_ARCHIVE`) بعد إصلاح التسمية + الـaliases:
  - rows = 137,985، والقيمة = 308,139,541.92.
  - per-chain متطابق.
  - **digest الأسماء = `169:a72b9bdd9a7dfddd`** (نفس main).
  - مجموع كل عميل (rows/value) متطابق اسم باسم.
  - **صفر أسماء في quarantine.**
- in25 و Clean: zero diff.
- تست وحدة: اسم شبه alias (fuzzy) ما يتحوّلش.

**خطر البيانات:** صفر لو الـparity متطابق. الـalias بيرجّع للاسم المخزّن حالياً بالظبط.

---

## ITEM7_84.csv
- **المسار:** `/workspace/tds-livetest/ITEM7_84.csv` (UTF-8 BOM).
- **الأعمدة:** old_name, new_name, chain, chain_prod_rules, file, rows, amount, old_status, new_name_also_present_today.
- **مصدر الأرقام:** الـharness على main (in-memory) لملف in26.
- **`chain`:** السلسلة في الـharness، وهي fathalla للـ84 كلهم.
- **`chain_prod_rules`:** بعد تطبيق `SELLIN_CUSTOMER_CHAIN_MAP` بتاع prod.

| chain_prod_rules | أسماء | صفوف | amount (EGP) |
|---|---|---|---|
| gomla (كيه اتش) | 60 | 69,713 | 109,273,865.61 |
| zahran | 22 | 6,346 | 5,328,793.07 |
| chain-1080314 (المنصوره) | 2 | 2,143 | 13,344,368.56 |
| **الإجمالي** | **84** | **78,202** | **127,947,027.24** |

## عدد المستخدمين حسب الدور (prod tenant_users، قراءة فقط، أعداد بس) — 3 نوفمبر 2026

| التينانت | الدور | العدد |
|---|---|---|
| adeco | vendor_admin | 1 (active) |
| system | super_admin | 1 |
| أي تينانت | national_sales_manager | **0** |
| أي تينانت | admin / chain_kam / field_supervisor / sales_user / viewer | 0 |

الإجمالي: 2 مستخدم حقيقي. مستخدمين الـseed اللي في الكود (nsm/kam/sup في adeco، admins لـunilever/pepsi) محتاجين ADECO_ROLE_USERS_SEED_PASSWORD أو متغيرات تانية مش متعرّفة على prod، فمحدش منهم يقدر يعمل login.

### مين هيخسر الرفع؟
ingestWriteRoles = super_admin + vendor_admin بس (رفع، dry-run، commit، discard، reapply، targets، product master). المسح (أي scope) وحذف الأرشيف = super_admin بس.
**محدش حقيقي هيخسر الرفع**: الاتنين الموجودين (vendor_admin و super_admin) لسه يقدروا. اللي اتقفل عليهم نظرياً: national_sales_manager (0 مستخدم)، admin القديم (0)، وأي دور تاني (0). الـvendor_admin الوحيد هيخسر بس «مسح البيانات» و«حذف من الأرشيف».

## بادئات store_id المجمّدة
qa_test→qa_ ، chain-1080314→cha ، zahran→zah (صريحة في frozenStoreIDPrefixes)؛ والباقي ثابت في الـswitch: carrefour، gomla، beet-elgomla، spinneys، metro، seoudi، kazyon، fathalla.

## أمان ENVIRONMENT على prod
prod: ENVIRONMENT=production و ALLOW_DEMO_TOKENS=false، فالـfatal الجديد (production + ALLOW_DEMO_TOKENS=true) مش هيوقّع السيرفر بالإعدادات الحالية.
