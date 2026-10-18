use std::cell::RefCell;
use std::io::{Read, Write};
use std::rc::Rc;

use aes::{Aes128, Aes192, Aes256};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use cipher::block_padding::Pkcs7;
use cipher::{BlockEncryptMut, KeyInit, KeyIvInit};
use flate2::read::ZlibDecoder;
use flate2::write::ZlibEncoder;
use flate2::Compression;
use md5::{Digest, Md5};
use rand::RngCore;
use rquickjs::{Context, Function, Runtime};
use rsa::pkcs1::DecodeRsaPublicKey;
use rsa::pkcs8::DecodePublicKey;
use rsa::traits::PublicKeyParts;
use rsa::RsaPublicKey;
use serde_json::{json, Value};

use crate::http;
use crate::model::SourceInfo;

const LX_POLYFILL: &str = r##"
const HEX = "0123456789abcdef";

function __mf_hexToBytes(hex) {
  var n = (hex || "").length >> 1;
  var out = new Uint8Array(n);
  for (var i = 0; i < n; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

function __mf_bytesToHex(bytes) {
  var out = "";
  for (var i = 0; i < bytes.length; i++) {
    var h = bytes[i].toString(16);
    out += h.length === 1 ? "0" + h : h;
  }
  return out;
}

class MFBuffer extends Uint8Array {
  static from(value, encoding) {
    if (value instanceof MFBuffer) return new MFBuffer(value);
    if (typeof value === "string") {
      return new MFBuffer(__mf_hexToBytes(__mf_encode(value, encoding || "utf8")));
    }
    if (value instanceof ArrayBuffer) return new MFBuffer(new Uint8Array(value));
    if (ArrayBuffer.isView(value)) {
      return new MFBuffer(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
    }
    if (Array.isArray(value)) return new MFBuffer(value);
    if (value && typeof value.length === "number") return new MFBuffer(value);
    return new MFBuffer(0);
  }
  static alloc(size) { return new MFBuffer(size); }
  static allocUnsafe(size) { return new MFBuffer(size); }
  static isBuffer(value) { return value instanceof MFBuffer; }
  static byteLength(value, encoding) { return MFBuffer.from(value, encoding).length; }
  static concat(list, totalLength) {
    var total = totalLength === undefined
      ? list.reduce(function (sum, item) { return sum + item.length; }, 0)
      : totalLength;
    var out = new MFBuffer(total);
    var offset = 0;
    for (var i = 0; i < list.length && offset < total; i++) {
      var item = list[i];
      var take = Math.min(item.length, total - offset);
      out.set(item.subarray(0, take), offset);
      offset += take;
    }
    return out;
  }
  toString(encoding, start, end) {
    var view = this.subarray(
      start === undefined ? 0 : start,
      end === undefined ? this.length : end
    );
    return __mf_decode(__mf_bytesToHex(view), encoding || "utf8");
  }
  equals(other) {
    if (this.length !== other.length) return false;
    for (var i = 0; i < this.length; i++) if (this[i] !== other[i]) return false;
    return true;
  }
  toJSON() { return { type: "Buffer", data: Array.from(this) }; }
}

globalThis.Buffer = MFBuffer;
globalThis.window = globalThis;
globalThis.self = globalThis;
globalThis.global = globalThis;
globalThis.process = globalThis.process || { env: {}, platform: "desktop", version: "v20.0.0" };

class MFTextEncoder {
  encode(value) { return MFBuffer.from(String(value), "utf8"); }
}
class MFTextDecoder {
  decode(value) { return MFBuffer.from(value).toString("utf8"); }
}
globalThis.TextEncoder = MFTextEncoder;
globalThis.TextDecoder = MFTextDecoder;

globalThis.atob = function (value) { return MFBuffer.from(value, "base64").toString("binary"); };
globalThis.btoa = function (value) { return MFBuffer.from(value, "binary").toString("base64"); };

class MFSearchParams {
  constructor(init) {
    this._pairs = [];
    if (typeof init === "string" && init.length) {
      init.split("&").forEach(function (part) {
        if (!part) return;
        var index = part.indexOf("=");
        var key = index < 0 ? part : part.slice(0, index);
        var value = index < 0 ? "" : part.slice(index + 1);
        this._pairs.push([decodeURIComponent(key.replace(/\+/g, " ")), decodeURIComponent(value.replace(/\+/g, " "))]);
      }, this);
    } else if (init && typeof init === "object") {
      Object.keys(init).forEach(function (key) { this._pairs.push([String(key), String(init[key])]); }, this);
    }
  }
  append(key, value) { this._pairs.push([String(key), String(value)]); }
  set(key, value) {
    this._pairs = this._pairs.filter(function (pair) { return pair[0] !== String(key); });
    this.append(key, value);
  }
  get(key) {
    var found = this._pairs.find(function (pair) { return pair[0] === String(key); });
    return found ? found[1] : null;
  }
  getAll(key) {
    return this._pairs.filter(function (pair) { return pair[0] === String(key); }).map(function (pair) { return pair[1]; });
  }
  delete(key) { this._pairs = this._pairs.filter(function (pair) { return pair[0] !== String(key); }); }
  toString() {
    return this._pairs.map(function (pair) {
      return encodeURIComponent(pair[0]) + "=" + encodeURIComponent(pair[1]);
    }).join("&");
  }
}

class MFURL {
  constructor(input, base) {
    var raw = String(input);
    if (base && !/^[a-z]+:\/\//i.test(raw)) {
      raw = String(base).replace(/\/$/, "") + "/" + raw.replace(/^\//, "");
    }
    this.href = raw;
    var match = raw.match(/^([a-z]+:\/\/[^/]+)(\/[^?]*)?(\?[^#]*)?/i);
    this.origin = match ? match[1] : "";
    this.pathname = match && match[2] ? match[2] : "/";
    this.search = match && match[3] ? match[3] : "";
    this.searchParams = new MFSearchParams(this.search.replace(/^\?/, ""));
    this.protocol = this.origin.split(":")[0] + ":";
  }
  toString() { return this.href; }
  toJSON() { return this.href; }
}
globalThis.URLSearchParams = MFSearchParams;
globalThis.URL = MFURL;

globalThis.encodeURIComponent = globalThis.encodeURIComponent || function (value) { return String(value); };
globalThis.decodeURIComponent = globalThis.decodeURIComponent || function (value) { return String(value); };

globalThis.setTimeout = function (fn) { try { fn(); } catch (e) { __mf_log(String(e)); } return 0; };
globalThis.setInterval = function () { return 0; };
globalThis.clearTimeout = function () {};
globalThis.clearInterval = function () {};
globalThis.queueMicrotask = function (fn) { Promise.resolve().then(fn); };

globalThis.console = {
  log: function () { __mf_log(Array.prototype.map.call(arguments, function (v) { try { return typeof v === "string" ? v : JSON.stringify(v); } catch (e) { return String(v); } }).join(" ")); },
  warn: function () { __mf_log(Array.prototype.map.call(arguments, String).join(" ")); },
  error: function () { __mf_log(Array.prototype.map.call(arguments, String).join(" ")); },
  debug: function () {}
};

globalThis.globalThis.crypto = {
  randomBytes: function (size) { return MFBuffer.from(__mf_hexToBytes(__mf_random(size))); }
};

function require(name) {
  if (name === "crypto") return globalThis.crypto;
  if (name === "zlib") return lx.utils.zlib;
  return {};
}
globalThis.require = require;

var __mf_script_info_json = globalThis.__mf_script_info || "{}";
var __mf_script_info = {};
try { __mf_script_info = JSON.parse(__mf_script_info_json); } catch (e) {}

var __mf_handler = null;
var __mf_done = false;
var __mf_result = null;
var __mf_error = null;

var lx = {
  EVENT_NAMES: { request: "request", inited: "inited", updateAlert: "updateAlert" },
  env: "desktop",
  version: "2.0.0",
  currentScriptInfo: __mf_script_info,
  on: function (eventName, handler) {
    if (eventName === "request") __mf_handler = handler;
    return Promise.resolve();
  },
  send: function (eventName, data) {
    if (eventName === "inited") {
      __mf_inited(JSON.stringify(data));
    } else if (eventName === "updateAlert") {
      __mf_log("updateAlert: " + JSON.stringify(data));
    }
    return Promise.resolve();
  },
  request: function (url, options, callback) {
    var raw = __mf_http(url, JSON.stringify(options || {}));
    var payload = {};
    try { payload = JSON.parse(raw); } catch (e) { payload = { error: String(e) }; }
    if (payload.error) {
      if (typeof callback === "function") {
        try { callback(new Error(payload.error), null, null); } catch (e) { __mf_log(String(e)); }
      }
      return function () {};
    }
    var response = {
      statusCode: payload.statusCode,
      statusMessage: payload.statusMessage,
      headers: payload.headers || {},
      bytes: payload.bytes || 0,
      raw: MFBuffer.from(payload.raw || "", "base64"),
      body: payload.body
    };
    if (typeof callback === "function") {
      try { callback(null, response, response.body); } catch (e) { __mf_log(String(e)); }
    }
    return function () {};
  },
  utils: {
    crypto: {
      aesEncrypt: function (buffer, mode, key, iv) {
        var out = __mf_aes(
          __mf_bytesToHex(MFBuffer.from(buffer)),
          mode,
          __mf_bytesToHex(MFBuffer.from(key)),
          iv ? __mf_bytesToHex(MFBuffer.from(iv)) : ""
        );
        return MFBuffer.from(__mf_hexToBytes(out));
      },
      rsaEncrypt: function (buffer, key) {
        var out = __mf_rsa(__mf_bytesToHex(MFBuffer.from(buffer)), key);
        return MFBuffer.from(__mf_hexToBytes(out));
      },
      randomBytes: function (size) {
        return MFBuffer.from(__mf_hexToBytes(__mf_random(size)));
      },
      md5: function (value) { return __mf_md5(String(value)); }
    },
    buffer: {
      from: function () { return MFBuffer.from.apply(MFBuffer, arguments); },
      bufToString: function (buffer, format) { return MFBuffer.from(buffer).toString(format); }
    },
    zlib: {
      inflate: function (buffer) {
        return Promise.resolve(MFBuffer.from(__mf_hexToBytes(__mf_inflate(__mf_bytesToHex(MFBuffer.from(buffer))))));
      },
      deflate: function (buffer) {
        return Promise.resolve(MFBuffer.from(__mf_hexToBytes(__mf_deflate(__mf_bytesToHex(MFBuffer.from(buffer))))));
      }
    }
  }
};
globalThis.lx = lx;

globalThis.__mf_begin = function (payloadJson) {
  __mf_done = false;
  __mf_result = null;
  __mf_error = null;
  var payload = JSON.parse(payloadJson);
  if (typeof __mf_handler !== "function") {
    __mf_error = "音源没有注册 request 处理器";
    __mf_done = true;
    return;
  }
  Promise.resolve()
    .then(function () { return __mf_handler(payload); })
    .then(function (result) {
      try { __mf_result = JSON.stringify(result === undefined ? null : result); }
      catch (e) { __mf_error = String(e); }
      __mf_done = true;
    })
    .catch(function (error) {
      __mf_error = String(error && (error.stack || error.message) || error);
      __mf_done = true;
    });
};
"##;

fn hex_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn hex_decode(value: &str) -> Vec<u8> {
    if value.len() % 2 != 0 {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(value.len() / 2);
    let bytes = value.as_bytes();
    let mut index = 0;
    while index + 1 < bytes.len() {
        let high = (bytes[index] as char).to_digit(16);
        let low = (bytes[index + 1] as char).to_digit(16);
        if let (Some(high), Some(low)) = (high, low) {
            out.push((high * 16 + low) as u8);
        }
        index += 2;
    }
    out
}

fn host_encode(value: &str, encoding: &str) -> String {
    let encoding = encoding.to_ascii_lowercase();
    let bytes = match encoding.as_str() {
        "base64" => BASE64.decode(value).unwrap_or_default(),
        "hex" => hex_decode(value),
        "binary" | "latin1" | "ascii" => value.chars().map(|c| c as u8).collect(),
        _ => value.as_bytes().to_vec(),
    };
    hex_encode(&bytes)
}

fn host_decode(hex: &str, encoding: &str) -> String {
    let bytes = hex_decode(hex);
    match encoding.to_ascii_lowercase().as_str() {
        "base64" => BASE64.encode(&bytes),
        "hex" => hex_encode(&bytes),
        "binary" | "latin1" | "ascii" => bytes.iter().map(|b| *b as char).collect(),
        _ => String::from_utf8_lossy(&bytes).to_string(),
    }
}

fn host_http(url: &str, options_json: &str) -> String {
    match do_http(url, options_json) {
        Ok(value) => value.to_string(),
        Err(error) => json!({ "error": error }).to_string(),
    }
}

fn do_http(url: &str, options_json: &str) -> Result<Value, String> {
    let options: Value = serde_json::from_str(options_json).unwrap_or_else(|_| json!({}));
    let method = options
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or("GET")
        .to_ascii_uppercase();
    let agent = http::agent();

    let mut headers: Vec<(String, String)> = Vec::new();
    if let Some(values) = options.get("headers").and_then(Value::as_object) {
        for (name, value) in values {
            if let Some(value) = value.as_str() {
                headers.push((name.clone(), value.to_string()));
            }
        }
    }
    let mut content_type_set = headers
        .iter()
        .any(|(name, _)| name.eq_ignore_ascii_case("content-type"));

    let mut body: Option<String> = None;
    if let Some(form) = options.get("form").and_then(Value::as_object) {
        let pairs: Vec<String> = form
            .iter()
            .map(|(key, value)| {
                format!(
                    "{}={}",
                    urlencoding::encode(key),
                    urlencoding::encode(&value.as_str().unwrap_or("").to_string())
                )
            })
            .collect();
        body = Some(pairs.join("&"));
        if !content_type_set {
            headers.push(("Content-Type".into(), "application/x-www-form-urlencoded".into()));
            content_type_set = true;
        }
    } else if let Some(value) = options.get("body") {
        if let Some(text) = value.as_str() {
            body = Some(text.to_string());
        } else {
            body = Some(serde_json::to_string(value).unwrap_or_default());
            if !content_type_set {
                headers.push(("Content-Type".into(), "application/json".into()));
            }
        }
    }

    macro_rules! with_headers {
        ($builder:expr) => {{
            let mut builder = $builder;
            for (name, value) in &headers {
                builder = builder.header(name, value);
            }
            builder
        }};
    }

    let response = match method.as_str() {
        "POST" => with_headers!(agent.post(url)).send(body.unwrap_or_default()),
        "PUT" => with_headers!(agent.put(url)).send(body.unwrap_or_default()),
        "PATCH" => with_headers!(agent.patch(url)).send(body.unwrap_or_default()),
        "DELETE" => with_headers!(agent.delete(url)).call(),
        "HEAD" => with_headers!(agent.head(url)).call(),
        _ => with_headers!(agent.get(url)).call(),
    };

    let mut response = response.map_err(|error| format!("请求失败: {error}"))?;

    let status_code = response.status().as_u16();
    let status_message = response.status().canonical_reason().unwrap_or("").to_string();
    let headers = response
        .headers()
        .iter()
        .filter_map(|(name, value)| value.to_str().ok().map(|v| (name.to_string(), Value::String(v.to_string()))))
        .collect::<serde_json::Map<String, Value>>();

    let bytes = response
        .body_mut()
        .read_to_vec()
        .map_err(|error| format!("读取响应失败: {error}"))?;
    let text = String::from_utf8_lossy(&bytes).to_string();
    let parsed_body = serde_json::from_str::<Value>(&text).unwrap_or_else(|_| Value::String(text.clone()));

    Ok(json!({
        "statusCode": status_code,
        "statusMessage": status_message,
        "headers": headers,
        "bytes": bytes.len(),
        "raw": BASE64.encode(&bytes),
        "body": parsed_body
    }))
}

fn host_aes(data_hex: &str, mode: &str, key_hex: &str, iv_hex: &str) -> String {
    let data = hex_decode(data_hex);
    let key = hex_decode(key_hex);
    let iv = hex_decode(iv_hex);
    let mode = mode.to_ascii_lowercase();
    let parts: Vec<&str> = mode.split('-').collect();
    let bits = parts.get(1).copied().unwrap_or("128");
    let chain = parts.get(2).copied().unwrap_or("cbc");

    macro_rules! run_cbc {
        ($cipher:ty) => {{
            match cbc::Encryptor::<$cipher>::new_from_slices(&key, &iv) {
                Ok(cipher) => hex_encode(&cipher.encrypt_padded_vec_mut::<Pkcs7>(&data)),
                Err(_) => String::new(),
            }
        }};
    }
    macro_rules! run_ecb {
        ($cipher:ty) => {{
            match ecb::Encryptor::<$cipher>::new_from_slice(&key) {
                Ok(cipher) => hex_encode(&cipher.encrypt_padded_vec_mut::<Pkcs7>(&data)),
                Err(_) => String::new(),
            }
        }};
    }

    match (bits, chain) {
        ("256", "cbc") => run_cbc!(Aes256),
        ("192", "cbc") => run_cbc!(Aes192),
        ("256", "ecb") => run_ecb!(Aes256),
        ("192", "ecb") => run_ecb!(Aes192),
        (_, "ecb") => run_ecb!(Aes128),
        _ => run_cbc!(Aes128),
    }
}

fn host_rsa(data_hex: &str, pem: &str) -> String {
    let data = hex_decode(data_hex);
    let key = RsaPublicKey::from_public_key_pem(pem)
        .or_else(|_| RsaPublicKey::from_pkcs1_pem(pem))
        .ok();
    let Some(key) = key else { return String::new() };
    let size = key.size();
    if data.len() > size {
        return String::new();
    }
    let mut padded = vec![0u8; size - data.len()];
    padded.extend_from_slice(&data);
    let message = rsa::BigUint::from_bytes_be(&padded);
    let encrypted = message.modpow(key.e(), key.n());
    let mut bytes = encrypted.to_bytes_be();
    while bytes.len() < size {
        bytes.insert(0, 0);
    }
    hex_encode(&bytes)
}

fn host_inflate(data_hex: &str) -> String {
    let data = hex_decode(data_hex);
    let mut decoder = ZlibDecoder::new(&data[..]);
    let mut out = Vec::new();
    if decoder.read_to_end(&mut out).is_ok() {
        hex_encode(&out)
    } else {
        String::new()
    }
}

fn host_deflate(data_hex: &str) -> String {
    let data = hex_decode(data_hex);
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
    if encoder.write_all(&data).is_err() {
        return String::new();
    }
    match encoder.finish() {
        Ok(out) => hex_encode(&out),
        Err(_) => String::new(),
    }
}

fn host_md5(value: &str) -> String {
    let digest = Md5::digest(value.as_bytes());
    hex_encode(&digest)
}

fn host_random(size: usize) -> String {
    let mut bytes = vec![0u8; size.min(1024 * 1024)];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex_encode(&bytes)
}

struct RunOutput {
    inited: Option<Value>,
    result: Option<Value>,
}

fn run_script(script: &str, info: &SourceInfo, action: Option<Value>, online: bool) -> Result<RunOutput, String> {
    let runtime = Runtime::new().map_err(|e| format!("创建 JS 运行时失败: {e}"))?;
    let context = Context::full(&runtime).map_err(|e| format!("创建 JS 上下文失败: {e}"))?;
    let inited_store: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
    let info_json = serde_json::to_string(&json!({
        "name": info.name,
        "description": info.description,
        "version": info.version,
        "author": info.author,
        "homepage": info.homepage,
    }))
    .unwrap_or_else(|_| "{}".into());

    context.with(|ctx| -> Result<(), String> {
        let globals = ctx.globals();
        let inited_for_js = inited_store.clone();
        let inited_fn = Function::new(ctx.clone(), move |json: String| {
            *inited_for_js.borrow_mut() = Some(json);
        })
        .map_err(|e| e.to_string())?;
        globals.set("__mf_inited", inited_fn).map_err(|e| e.to_string())?;

        let http_fn = Function::new(ctx.clone(), move |url: String, options: String| -> String {
            if online {
                host_http(&url, &options)
            } else {
                json!({ "error": "音源导入探测：跳过网络请求" }).to_string()
            }
        })
        .map_err(|e| e.to_string())?;
        globals.set("__mf_http", http_fn).map_err(|e| e.to_string())?;

        let aes_fn = Function::new(
            ctx.clone(),
            |data: String, mode: String, key: String, iv: String| -> String {
                host_aes(&data, &mode, &key, &iv)
            },
        )
        .map_err(|e| e.to_string())?;
        globals.set("__mf_aes", aes_fn).map_err(|e| e.to_string())?;

        let rsa_fn = Function::new(ctx.clone(), |data: String, key: String| -> String {
            host_rsa(&data, &key)
        })
        .map_err(|e| e.to_string())?;
        globals.set("__mf_rsa", rsa_fn).map_err(|e| e.to_string())?;

        let random_fn = Function::new(ctx.clone(), |size: usize| -> String { host_random(size) })
            .map_err(|e| e.to_string())?;
        globals.set("__mf_random", random_fn).map_err(|e| e.to_string())?;

        let md5_fn = Function::new(ctx.clone(), |value: String| -> String { host_md5(&value) })
            .map_err(|e| e.to_string())?;
        globals.set("__mf_md5", md5_fn).map_err(|e| e.to_string())?;

        let inflate_fn = Function::new(ctx.clone(), |data: String| -> String { host_inflate(&data) })
            .map_err(|e| e.to_string())?;
        globals.set("__mf_inflate", inflate_fn).map_err(|e| e.to_string())?;

        let deflate_fn = Function::new(ctx.clone(), |data: String| -> String { host_deflate(&data) })
            .map_err(|e| e.to_string())?;
        globals.set("__mf_deflate", deflate_fn).map_err(|e| e.to_string())?;

        let encode_fn = Function::new(ctx.clone(), |value: String, encoding: String| -> String {
            host_encode(&value, &encoding)
        })
        .map_err(|e| e.to_string())?;
        globals.set("__mf_encode", encode_fn).map_err(|e| e.to_string())?;

        let decode_fn = Function::new(ctx.clone(), |value: String, encoding: String| -> String {
            host_decode(&value, &encoding)
        })
        .map_err(|e| e.to_string())?;
        globals.set("__mf_decode", decode_fn).map_err(|e| e.to_string())?;

        let log_fn = Function::new(ctx.clone(), |value: String| {
            eprintln!("[MusicFox LX] {value}");
        })
        .map_err(|e| e.to_string())?;
        globals.set("__mf_log", log_fn).map_err(|e| e.to_string())?;

        globals
            .set("__mf_script_info", info_json)
            .map_err(|e| e.to_string())?;

        ctx.eval::<(), _>(LX_POLYFILL)
            .map_err(|e| format!("加载 LX 运行环境失败: {e}"))?;
        ctx.eval::<(), _>(script)
            .map_err(|e| format!("加载音源脚本失败: {e}"))?;

        if let Some(payload) = action.clone() {
            let begin: Function = globals
                .get("__mf_begin")
                .map_err(|e| format!("读取音源处理器失败: {e}"))?;
            begin
                .call::<_, ()>((payload.to_string(),))
                .map_err(|e| format!("调用音源失败: {e}"))?;
        }

        Ok(())
    })?;

    for _ in 0..20_000 {
        match runtime.execute_pending_job() {
            Ok(true) => continue,
            Ok(false) => break,
            Err(error) => return Err(format!("音源异步任务失败: {error}")),
        }
    }

    let inited = inited_store
        .borrow()
        .clone()
        .and_then(|raw| serde_json::from_str::<Value>(&raw).ok());

    let (done, result_text, error_text) = context.with(|ctx| {
        let globals = ctx.globals();
        let done: bool = globals.get::<_, bool>("__mf_done").unwrap_or(false);
        let result: Option<String> = globals.get("__mf_result").unwrap_or(None);
        let error: Option<String> = globals.get("__mf_error").unwrap_or(None);
        (done, result, error)
    });

    let result = if action.is_some() {
        if !done {
            return Err("音源处理超时".into());
        }
        if let Some(error) = error_text {
            if !error.is_empty() {
                return Err(error);
            }
        }
        result_text.and_then(|raw| serde_json::from_str::<Value>(&raw).ok())
    } else {
        None
    };

    Ok(RunOutput { inited, result })
}

pub fn probe_script(script: &str, info: &SourceInfo) -> Result<Value, String> {
    let output = run_script(script, info, None, false)?;
    Ok(output.inited.unwrap_or(Value::Null))
}

pub fn resolve(
    script: &str,
    info: &SourceInfo,
    provider: &str,
    quality: &str,
    music_info: Value,
) -> Result<String, String> {
    let payload = json!({
        "source": provider,
        "action": "musicUrl",
        "info": {
            "type": quality,
            "musicInfo": music_info
        }
    });
    let output = run_script(script, info, Some(payload), true)?;
    let result = output.result.ok_or_else(|| "音源没有返回结果".to_string())?;
    let url = match result {
        Value::String(url) => url,
        Value::Object(object) => object
            .get("url")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        _ => String::new(),
    };
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err("音源没有返回有效地址".into());
    }
    Ok(url)
}

pub fn lyric(
    script: &str,
    info: &SourceInfo,
    provider: &str,
    music_info: Value,
) -> Result<String, String> {
    let payload = json!({
        "source": provider,
        "action": "lyric",
        "info": {
            "type": "128k",
            "musicInfo": music_info
        }
    });
    let output = run_script(script, info, Some(payload), true)?;
    let result = output.result.ok_or_else(|| "音源没有返回歌词".to_string())?;
    let lyric = match result {
        Value::String(text) => text,
        Value::Object(object) => object
            .get("lyric")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        _ => String::new(),
    };
    if lyric.trim().is_empty() {
        return Err("音源没有返回歌词".into());
    }
    Ok(lyric)
}

pub fn read_script(path: &str) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("读取音源脚本失败: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn info() -> SourceInfo {
        SourceInfo {
            id: "test".into(),
            name: "Test LX".into(),
            description: String::new(),
            author: String::new(),
            version: "1".into(),
            homepage: String::new(),
            script_path: String::new(),
            enabled: true,
            sources: vec!["wy".into()],
            status: String::new(),
        }
    }

    const SCRIPT: &str = r#"
lx.on('request', async function (request) {
  if (request.action === 'musicUrl') {
    return 'https://example.com/' + request.source + '/' + request.info.musicInfo.songmid + '.' + request.info.type;
  }
  if (request.action === 'lyric') {
    return { lyric: '[00:01.00]hello' };
  }
  throw new Error('unknown action');
});
lx.send('inited', {
  status: true,
  sources: { wy: { name: 'wy', type: 'music', actions: ['musicUrl', 'lyric'], qualitys: ['128k', 'flac'] } }
});
"#;

    #[test]
    fn runs_lx_request_handler() {
        let url = resolve(
            SCRIPT,
            &info(),
            "wy",
            "flac",
            json!({ "songmid": "123", "name": "test" }),
        )
        .expect("resolve");
        assert_eq!(url, "https://example.com/wy/123.flac");

        let lyric = lyric(
            SCRIPT,
            &info(),
            "wy",
            json!({ "songmid": "123" }),
        )
        .expect("lyric");
        assert!(lyric.contains("hello"));
    }

    #[test]
    fn probes_inited_sources() {
        let inited = probe_script(SCRIPT, &info()).expect("probe");
        assert_eq!(inited["sources"]["wy"]["type"], "music");
    }
}

#[cfg(test)]
mod external_tests {
    use super::*;

    #[test]
    fn probes_real_pdone_script_if_available() {
        let path = "/tmp/opencode/lx-latest.js";
        let Ok(script) = std::fs::read_to_string(path) else { return };
        let info = SourceInfo {
            id: "pdone".into(),
            name: "独家音源".into(),
            description: String::new(),
            author: "w".into(),
            version: "6".into(),
            homepage: String::new(),
            script_path: path.into(),
            enabled: true,
            sources: vec![],
            status: String::new(),
        };
        let inited = probe_script(&script, &info).expect("probe real script");
        eprintln!("inited: {}", serde_json::to_string_pretty(&inited).unwrap());
        assert!(inited["sources"].is_object());
    }
}
