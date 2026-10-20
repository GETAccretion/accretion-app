//! Accretion: Apple ID (7-day) signing for the iOS app.
//!
//! A thin C layer over Impactor's `plume_core` and `plume_utils` (MPL-2.0), the same sign-in,
//! developer-services and signing flow as plumesign. Requests and answers are JSON strings.
//! Rules: nothing is logged, nothing secret is written to disk except the certificate key, which
//! exists only inside the caller's work folder for the length of one `sign` call. Tokens and the
//! key are handed back to the caller, which keeps them in the Keychain.

use std::ffi::{CStr, CString, c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use plume_core::auth::{Account, TwoFactorAction, TwoFactorMethod, TwoFactorRequest};
use plume_core::developer::DeveloperSession;
use plume_core::{AnisetteConfiguration, CertificateIdentity};
use plume_utils::{Bundle, PlistInfoTrait, Signer, SignerAppReal, SignerOptions};
use serde::Deserialize;
use serde_json::{Value, json};

/// Asks the app something during a call (2FA code, certificate revoke). Receives a JSON request,
/// returns a JSON answer allocated with `malloc` (the library frees it), or NULL to cancel.
pub type PromptCallback =
    extern "C" fn(context: *mut c_void, request_json: *const c_char) -> *mut c_char;

struct Prompt {
    callback: PromptCallback,
    context: *mut c_void,
}

impl Prompt {
    fn ask(&self, request: Value) -> Option<Value> {
        let request = CString::new(request.to_string()).ok()?;
        let answer = (self.callback)(self.context, request.as_ptr());
        if answer.is_null() {
            return None;
        }
        // SAFETY: the callback returns a NUL-terminated string from malloc (see header).
        let parsed = unsafe { CStr::from_ptr(answer) }
            .to_str()
            .ok()
            .and_then(|text| serde_json::from_str(text).ok());
        unsafe { libc::free(answer as *mut c_void) };
        parsed
    }
}

fn runtime() -> Result<&'static tokio::runtime::Runtime, String> {
    static RUNTIME: OnceLock<Result<tokio::runtime::Runtime, String>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| {
            // Same TLS provider as plumesign.
            let _ = rustls::crypto::ring::default_provider().install_default();
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .map_err(|e| format!("Could not start: {e}"))
        })
        .as_ref()
        .map_err(Clone::clone)
}

#[derive(Deserialize)]
struct AnisetteRequest {
    url: String,
    state_dir: String,
}

impl AnisetteRequest {
    fn config(&self) -> AnisetteConfiguration {
        AnisetteConfiguration::default()
            .set_configuration_path(PathBuf::from(&self.state_dir))
            .set_anisette_url_v3(self.url.trim_end_matches('/').to_string())
            .set_remote_only(true)
    }
}

#[derive(Deserialize)]
struct SessionTokens {
    adsid: String,
    token: String,
}

#[derive(Deserialize)]
struct LoginRequest {
    email: String,
    password: String,
    anisette: AnisetteRequest,
}

#[derive(Deserialize)]
struct CallRequest {
    op: String,
    session: SessionTokens,
    anisette: AnisetteRequest,
    #[serde(default)]
    team_id: String,
    #[serde(default)]
    udid: String,
    #[serde(default)]
    device_name: String,
    // sign
    #[serde(default)]
    app_path: String,
    #[serde(default)]
    work_dir: String,
    #[serde(default)]
    key_pem: Option<String>,
    #[serde(default)]
    machine_name: Option<String>,
    #[serde(default)]
    remove_extensions: bool,
}

fn date(value: &plist::Date) -> String {
    value.to_xml_format()
}

async fn login(request: LoginRequest, prompt: &Prompt) -> Result<Value, String> {
    let email = request.email;
    let password = request.password;
    let credentials = || -> Result<(String, String), String> { Ok((email.clone(), password.clone())) };
    let two_factor = |req: TwoFactorRequest| -> Result<TwoFactorAction, String> {
        let method = match req.method {
            TwoFactorMethod::Sms => "sms",
            _ => "device",
        };
        let phones: Vec<Value> = req
            .trusted_phone_numbers
            .iter()
            .map(|p| json!({"id": p.id, "last_two": p.last_two_digits}))
            .collect();
        let answer = prompt
            .ask(json!({"kind": "two_factor", "method": method, "phones": phones}))
            .ok_or("Cancelled")?;
        match answer["action"].as_str() {
            Some("code") => Ok(TwoFactorAction::SubmitCode(
                answer["code"].as_str().unwrap_or_default().trim().to_string(),
            )),
            Some("sms") => {
                let id = answer["phone_id"].as_u64().ok_or("No phone chosen")?;
                Ok(TwoFactorAction::SendSms(
                    u32::try_from(id).map_err(|_| "No phone chosen")?,
                ))
            }
            _ => Err("Cancelled".into()),
        }
    };

    let account = Account::login(credentials, two_factor, request.anisette.config())
        .await
        .map_err(|e| e.to_string())?;
    let session = DeveloperSession::using_account(account)
        .await
        .map_err(|e| e.to_string())?;
    Ok(json!({"adsid": session.adsid(), "token": session.xcode_gs_token()}))
}

async fn call(request: CallRequest, prompt: &Prompt) -> Result<Value, String> {
    let session = DeveloperSession::new(
        request.session.adsid.clone(),
        request.session.token.clone(),
        request.anisette.config(),
    )
    .await
    .map_err(|e| e.to_string())?;
    let team = request.team_id.clone();

    match request.op.as_str() {
        "teams" => {
            let teams = session.qh_list_teams().await.map_err(|e| e.to_string())?;
            let list: Vec<Value> = teams
                .teams
                .iter()
                .map(|t| json!({"id": t.team_id, "name": t.name, "type": t._type, "status": t.status}))
                .collect();
            Ok(json!({"teams": list}))
        }
        "device_status" => {
            let device = session
                .qh_get_device(&team, &request.udid)
                .await
                .map_err(|e| e.to_string())?;
            let count = session
                .qh_list_devices(&team)
                .await
                .map_err(|e| e.to_string())?
                .devices
                .len();
            Ok(json!({"registered": device.is_some(), "count": count}))
        }
        "register_device" => {
            session
                .qh_ensure_device(&team, &request.device_name, &request.udid)
                .await
                .map_err(|e| e.to_string())?;
            Ok(json!({"registered": true}))
        }
        "app_ids" => {
            let ids = session.qh_list_app_ids(&team).await.map_err(|e| e.to_string())?;
            let list: Vec<&String> = ids.app_ids.iter().map(|a| &a.identifier).collect();
            Ok(json!({"identifiers": list}))
        }
        "certificates" => {
            let certs = session.qh_list_certs(&team).await.map_err(|e| e.to_string())?;
            let list: Vec<Value> = certs
                .certificates
                .iter()
                .map(|c| {
                    json!({
                        "name": c.name,
                        "serial": c.serial_number,
                        "status": c.status,
                        "expires": date(&c.expiration_date),
                        "machine_name": c.machine_name,
                    })
                })
                .collect();
            Ok(json!({"certificates": list}))
        }
        "sign" => sign(&session, &request, prompt).await,
        other => Err(format!("Unknown operation {other}")),
    }
}

/// The plumesign flow on an unpacked .app: certificate, device, bundle IDs with the team suffix,
/// App IDs, capabilities, app groups, profiles, codesign. Signs the folder in place.
async fn sign(session: &DeveloperSession, request: &CallRequest, prompt: &Prompt) -> Result<Value, String> {
    let team = &request.team_id;
    if request.work_dir.is_empty() || request.app_path.is_empty() {
        return Err("Missing work folder or app".into());
    }
    let work = PathBuf::from(&request.work_dir);
    let key_dir = work.join("keys").join(team);
    let key_path = key_dir.join("key.pem");

    let result = async {
        if let Some(key) = &request.key_pem {
            std::fs::create_dir_all(&key_dir).map_err(|e| e.to_string())?;
            std::fs::write(&key_path, key).map_err(|e| e.to_string())?;
        }

        let mut confirm_reset = || {
            prompt
                .ask(json!({"kind": "revoke_certificate"}))
                .is_some_and(|a| a["action"].as_str() == Some("yes"))
        };
        let identity = CertificateIdentity::new_with_session(
            session,
            work.clone(),
            request.machine_name.clone(),
            team,
            true,
            Some(&mut confirm_reset),
        )
        .await
        .map_err(|e| e.to_string())?;
        let certificate_new = identity.new;
        let serial = identity.serial_number.clone();
        let key_pem = std::fs::read_to_string(&key_path).map_err(|e| e.to_string())?;

        let app = Path::new(&request.app_path);
        if request.remove_extensions {
            // Each extension would cost one of the free account's 10 App IDs a week.
            for folder in ["PlugIns", "Extensions", "Watch"] {
                let path = app.join(folder);
                if path.exists() {
                    std::fs::remove_dir_all(&path).map_err(|e| e.to_string())?;
                }
            }
        }

        if !request.udid.is_empty() {
            session
                .qh_ensure_device(team, &request.device_name, &request.udid)
                .await
                .map_err(|e| e.to_string())?;
        }

        let bundle = Bundle::new(app).map_err(|e| e.to_string())?;
        let kind = SignerAppReal::from_bundle_identifier_and_name(
            bundle.get_bundle_identifier().as_deref(),
            bundle.get_bundle_name().as_deref(),
        );
        let mut signer = Signer::new(Some(identity), SignerOptions::new_for_app(kind.app));
        signer
            .modify_bundle(&bundle, &Some(team.clone()))
            .await
            .map_err(|e| e.to_string())?;
        signer
            .register_bundle(&bundle, session, team, false)
            .await
            .map_err(|e| e.to_string())?;
        signer.sign_bundle(&bundle).await.map_err(|e| e.to_string())?;

        let profiles: Vec<Value> = signer
            .provisioning_files
            .iter()
            .map(|p| json!({"bundle_id": p.bundle_id(), "expires": date(p.expiration_date())}))
            .collect();
        Ok::<Value, String>(json!({
            "bundle_id": bundle.get_bundle_identifier(),
            "certificate_new": certificate_new,
            "serial": serial,
            "key_pem": key_pem,
            "profiles": profiles,
        }))
    }
    .await;

    // The key never stays on disk.
    let _ = std::fs::remove_dir_all(work.join("keys"));
    result
}

fn answer(result: Result<Value, String>) -> *mut c_char {
    let value = match result {
        Ok(Value::Object(mut map)) => {
            map.insert("ok".into(), Value::Bool(true));
            Value::Object(map)
        }
        Ok(other) => json!({"ok": true, "value": other}),
        Err(message) => json!({"ok": false, "error": message}),
    };
    CString::new(value.to_string())
        .unwrap_or_else(|_| CString::from(c"{\"ok\":false,\"error\":\"Bad answer\"}"))
        .into_raw()
}

fn run<R: for<'de> Deserialize<'de>>(
    request_json: *const c_char,
    callback: PromptCallback,
    context: *mut c_void,
    work: impl AsyncFnOnce(R, &Prompt) -> Result<Value, String>,
) -> *mut c_char {
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        if request_json.is_null() {
            return Err("No request".to_string());
        }
        // SAFETY: the caller passes a NUL-terminated string (see header).
        let text = unsafe { CStr::from_ptr(request_json) }
            .to_str()
            .map_err(|_| "Request is not text".to_string())?;
        let request: R = serde_json::from_str(text).map_err(|e| format!("Bad request: {e}"))?;
        let prompt = Prompt { callback, context };
        runtime()?.block_on(work(request, &prompt))
    }));
    answer(outcome.unwrap_or_else(|_| Err("Apple ID signing stopped unexpectedly".into())))
}

/// Signs in with an Apple ID (SRP, 2FA through the prompt). Answer: {ok, adsid, token} or {ok:false, error}.
#[unsafe(no_mangle)]
pub extern "C" fn accretion_appleid_login(
    request_json: *const c_char,
    callback: PromptCallback,
    context: *mut c_void,
) -> *mut c_char {
    run(request_json, callback, context, async |r: LoginRequest, p: &Prompt| login(r, p).await)
}

/// Developer services for a signed-in session: teams, device_status, register_device, app_ids,
/// certificates, sign. Answer: {ok, ...} or {ok:false, error}.
#[unsafe(no_mangle)]
pub extern "C" fn accretion_appleid_call(
    request_json: *const c_char,
    callback: PromptCallback,
    context: *mut c_void,
) -> *mut c_char {
    run(request_json, callback, context, async |r: CallRequest, p: &Prompt| call(r, p).await)
}

/// Frees an answer, wiping it first (answers can hold tokens or a key).
#[unsafe(no_mangle)]
pub extern "C" fn accretion_appleid_free(answer: *mut c_char) {
    if answer.is_null() {
        return;
    }
    // SAFETY: `answer` came from CString::into_raw in this library.
    let mut bytes = unsafe { CString::from_raw(answer) }.into_bytes();
    for byte in bytes.iter_mut() {
        // SAFETY: writing to owned, valid memory.
        unsafe { std::ptr::write_volatile(byte, 0) };
    }
}
