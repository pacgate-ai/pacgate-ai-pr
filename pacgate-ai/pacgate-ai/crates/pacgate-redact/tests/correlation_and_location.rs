//! Cross-document correlation and location handling, from the 0.2.18 audit.
//!
//! Two findings, both about a value's identity surviving context:
//!
//!   P1-1  the same USCC under 统一社会信用代码 and 纳税人识别号 produced two
//!         different tokens, because the type code was inside the HMAC input.
//!         Since the three-in-one registration reform those are the SAME
//!         identifier for the same company, so cross-document correlation - the
//!         entire purpose of value-derived tokens - failed in its main case.
//!
//!   P2-1  an address was split into three tokens with the house number left in
//!         clear text, and `印尼` was redacted while `马来西亚 / 越南 / 菲律宾` were
//!         not, in the same paragraph.

use pacgate_core::DataLevel;
use pacgate_redact::detect::noise;
use pacgate_redact::detect::{tier_one_detectors, Detector, TierOneDetector};
use pacgate_redact::{EntityType, MappingVersion, Sanitizer, TokenKey};

/// ONE key for every case, because the question is whether CONTEXT changes the
/// token. Fresh `Sanitizer::new` calls derive different keys and every token would
/// differ for a reason unrelated to the defect.
fn key() -> TokenKey {
    TokenKey::from_secret(b"correlation-test-key")
}

fn sanitize_with(text: &str) -> String {
    let mut s = Sanitizer::with_key(tier_one_detectors(), MappingVersion::CURRENT, key());
    s.sanitize(text, DataLevel::T3ProjectSpecific)
        .expect("sanitize must not error")
        .text
}

fn first_token(text: &str) -> String {
    let out = sanitize_with(text);
    let start = out.find('[').unwrap_or_else(|| panic!("no token in {out:?}"));
    let end = out[start..]
        .find(']')
        .map(|i| start + i + 1)
        .unwrap_or_else(|| panic!("unterminated token in {out:?}"));
    out[start..end].to_string()
}

/// The HMAC tail must not depend on which keyword introduced the value.
///
/// MEASURED 2026-11-03 (before):
///   统一社会信用代码 91440300MA5FL8XY3K -> [USCC_5FED5402F3E018BA]
///   纳税人识别号   91440300MA5FL8XY3K -> [CN_TAX_ID_281023A22D30E06F]
///
/// The display prefix still differs - that is intentional, it tells a reviewer
/// which rule fired - but the TAG must be identical so the two documents join.
#[test]
fn the_same_entity_gets_one_tag_under_every_keyword() {
    let value = "91440300MA5FL8XY3K";
    let forms = [
        format!("统一社会信用代码 {value}"),
        format!("营业执照号 {value}"),
        format!("纳税人识别号 {value}"),
    ];

    let tags: Vec<String> = forms
        .iter()
        .map(|f| {
            let t = first_token(f);
            // `[PREFIX_TAG]` -> TAG
            t.trim_start_matches('[')
                .trim_end_matches(']')
                .rsplit_once('_')
                .map(|(_, tag)| tag.to_string())
                .unwrap_or_else(|| panic!("malformed token {t}"))
        })
        .collect();

    assert_eq!(
        tags[0], tags[1],
        "统一社会信用代码 and 营业执照号 disagree: {:?} vs {:?}",
        tags[0], tags[1]
    );
    assert_eq!(
        tags[0], tags[2],
        "USCC and TIN are the same code since 三证合一 but got different tags: {:?} vs {:?}",
        tags[0], tags[2]
    );
}

/// A bank account is one account whether or not the word 账号 precedes it.
#[test]
fn the_same_account_gets_one_tag_in_every_context() {
    let value = "6217900123456789010";
    let tags: Vec<String> = [value.to_string(), format!("账号 {value}")]
        .iter()
        .map(|f| {
            let t = first_token(f);
            t.trim_start_matches('[')
                .trim_end_matches(']')
                .rsplit_once('_')
                .map(|(_, tag)| tag.to_string())
                .expect("malformed token")
        })
        .collect();
    assert_eq!(tags[0], tags[1], "context changed the account tag");
}

/// Types that are genuinely DIFFERENT registries must not be merged.
///
/// This is the guard on the fix above: a 13-digit Thai tax id and a 13-digit
/// juristic id are both digits, and collapsing every type into one domain would
/// merge two unrelated registries into a single tag space.
#[test]
fn different_registries_keep_different_tags() {
    let th_tax = first_token("TaxID 3101401176368");
    let th_juristic = first_token("Juristic ID No.3101401176368");
    assert_ne!(
        th_tax, th_juristic,
        "a tax id and a juristic id are different registries and must not share a token"
    );
}

/// A complete address is ONE span covering the house number.
///
/// MEASURED 2026-11-03 (before): `北京市朝阳区建国路88号` became three LOCATION
/// tokens with `88号` left in clear text - unreadable, partly disclosed, and split
/// so the place could not be correlated across documents.
#[test]
fn a_complete_address_is_one_span() {
    let found = TierOneDetector::new()
        .detect("现住北京市朝阳区建国路88号，国籍中国。")
        .expect("detection works");
    let addrs: Vec<&str> = found
        .iter()
        .filter(|m| m.entity == EntityType::PostalAddress)
        .map(|m| m.text.as_str())
        .collect();
    assert_eq!(addrs.len(), 1, "an address must be one span, got {addrs:?}");
    assert!(
        addrs[0].ends_with("88号"),
        "the house number must be inside the span: {:?}",
        addrs[0]
    );
}

/// Ordinary contract text must not become an address.
///
/// The pattern requires 路/街/巷 plus a house number, which is what stops it from
/// swallowing any sentence that mentions a city. Both halves belong in one test.
#[test]
fn ordinary_contract_text_is_not_an_address() {
    for text in [
        "借款金额 1,250,000.00 元",
        "案号（2026）京0105民初12345号",
        "本案涉及印尼、马来西亚、越南、菲律宾四国当事人",
        "合同编号 PG-2026-0042",
    ] {
        let found = TierOneDetector::new().detect(text).expect("detection works");
        assert!(
            !found.iter().any(|m| m.entity == EntityType::PostalAddress),
            "false positive on {text:?}: {:?}",
            found.iter().map(|m| m.text.clone()).collect::<Vec<_>>()
        );
    }
}

/// Country names and capitals are public geography, in every spelling.
///
/// MEASURED 2026-11-03 (before): `印尼` was NOT suppressed while 印度尼西亚,
/// 马来西亚, 越南 and 菲律宾 were, so one paragraph redacted one country and left
/// three - which the audit read as inconsistency, and it was.
#[test]
fn country_names_and_capitals_are_public_in_every_spelling() {
    for name in [
        "印尼",
        "印度尼西亚",
        "马来西亚",
        "越南",
        "菲律宾",
        "中国",
        "北京",
        "上海",
        "雅加达",
        "东京",
        "新加坡",
    ] {
        assert!(
            noise::is_public_entity(name),
            "{name} is public geography and must not be redacted"
        );
    }
}

/// A private company or a street address must still be redacted.
#[test]
fn private_entities_are_not_excused() {
    for name in ["北京华宇软件股份有限公司", "朝阳区建国路88号", "张三"] {
        assert!(
            !noise::is_public_entity(name),
            "{name} is not public geography"
        );
    }
}

/// A public place in its administrative form is the same public place.
///
/// MEASURED 2026-11-09 on `equity-transfer-agreement` (doc 8b03bf9d): the
/// document blocked with residue exactly `上海市` + `浦东新区` and ZERO structural
/// survivors, so `GET /download` answered 409 forever and the only way out was
/// manual SQL. `上海` was in the list; `上海市` was not.
///
/// The asymmetry is the defect, not the missing entry: `广州市`, `深圳市`,
/// `杭州市` would each block the next document the same way. So the rule is the
/// administrative suffix, and it only applies when the stem is ALREADY listed.
#[test]
fn a_listed_place_in_its_administrative_form_is_still_public() {
    for name in [
        "上海市",
        "北京市",
        "天津市",
        "重庆市",
        "浦东新区",
        "广东省",
        "浙江省",
        "香港特别行政区",
    ] {
        assert!(
            noise::is_public_entity(name),
            "{name} is a listed public place in administrative form and must not block a document"
        );
    }
}

/// The suffix rule must not become a hole for a client's own district.
///
/// `朝阳区` is a real Beijing district and also where a client's office sits. It
/// is NOT suppressed, because `朝阳` is not a listed public place - the stem has
/// to be public geography before the suffix rule applies. This is the guard on
/// the fix above: without it, `is_administrative_form_of_public_place` would
/// excuse every 区/县/市 in the language.
#[test]
fn an_unlisted_district_is_not_excused_by_the_suffix_rule() {
    for name in [
        "朝阳区",
        "海淀区",
        "南山区",
        "余杭区",
        "昆山市",
        "义乌市",
    ] {
        assert!(
            !noise::is_public_entity(name),
            "{name} is not a listed public place and must still be redacted"
        );
    }
}

/// The end-to-end shape of the 2026-11-09 block, with the real detector set.
///
/// This is the regression that matters: the redactor and the verifier saw
/// DIFFERENT spans for the same place. On the way in the model emitted `上` (one
/// character, dropped) and `浦东新区` at 0.44 (below MIN_MODEL_CONFIDENCE), so
/// there was nothing to redact. On the way out it emitted `上海市` at 0.97 and
/// `浦东新区` at 0.65 - above every suppressor, so the verifier blocked on a
/// place name the redactor had been right to leave alone.
///
/// Requires the NER weights; skipped when `NER_MODEL_DIR` is unset so the suite
/// still runs without them.
#[test]
fn a_contract_signed_in_a_public_place_does_not_block() {
    let Ok(dir) = std::env::var("NER_MODEL_DIR") else {
        eprintln!("NER_MODEL_DIR unset - skipping the model-backed regression");
        return;
    };
    let detectors = pacgate_redact::detect::full_detectors(&dir).expect("model loads");
    let mut s = Sanitizer::with_key(detectors, MappingVersion::CURRENT, key());

    let text = "股权转让协议本协议由以下双方于二〇二五年六月十八日在上海市浦东新区签署：\
                转让方：杭州晨曦投资合伙企业（有限合伙），统一社会信用代码 91330100MA2XXXXXXX。\
                受让方：宁波远望创业投资有限公司，统一社会信用代码 91330200MA8YYYYYYY。";

    let out = s
        .sanitize(text, DataLevel::T3ProjectSpecific)
        .expect("sanitize must not error");

    assert!(
        !out.ledger.verdict.is_block(),
        "a contract signed in a public place must not block; residue was {:?}",
        out.ledger
            .residue
            .iter()
            .map(|r| r.text.clone())
            .collect::<Vec<_>>()
    );
    // The over-correction guard: the place is preserved AND the identities are not.
    assert!(out.text.contains("上海市浦东新区"), "the place must survive");
    assert!(!out.text.contains("91330100MA2XXXXXXX"), "USCC leaked");
    assert!(!out.text.contains("杭州晨曦投资合伙企业"), "org name leaked");
}

