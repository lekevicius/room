// Room's bridge to adblock-rust (MPL-2.0, //room/third_party/rust/adblock).
// One engine per browser process; built on a background sequence from the
// lists' text, matched on the UI thread (Engine is Send + Sync without the
// crate's single-thread feature). Domain resolution is Chromium's
// registry_controlled_domains, through room::adblock::HostDomainRange.

use std::collections::HashSet;

use adblock::lists::{FilterFormat, FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use adblock::url_parser::ResolvesDomain;
use adblock::Engine;

#[cxx::bridge(namespace = "room::adblock")]
mod ffi {
    /// One filter list's text as the host hands it over.
    struct ListInput {
        text: String,
        /// HOSTS format (one hostname per line) instead of ABP/uBO syntax.
        hosts: bool,
        /// The list may use privileged scriptlets (uBO's "trusted" ones).
        trusted: bool,
    }

    struct NetworkMatch {
        /// Block the request (an exception did not apply, or `important`).
        block: bool,
        /// An exception rule matched (logged, never blocked).
        exception: bool,
        /// `$redirect`: a data: URL with the resource to serve instead.
        redirect: String,
        /// `$removeparam`: the rewritten URL, if any parameter was removed.
        rewritten_url: String,
    }

    struct CosmeticResources {
        hide_selectors: Vec<String>,
        procedural_actions: Vec<String>,
        exceptions: Vec<String>,
        injected_script: String,
        generichide: bool,
    }

    unsafe extern "C++" {
        include!("room/core/content_blocking/domain_resolver.h");
        fn HostDomainRange(host: &str, start: &mut usize, end: &mut usize);
    }

    extern "Rust" {
        type AdblockEngine;

        /// Installs Chromium's domain resolver; idempotent.
        fn install_domain_resolver();
        /// Parses `lists` into a new engine and loads `resources_json`
        /// (adblock-rust's resource format; empty for none).
        fn new_engine(lists: &[ListInput], resources_json: &str) -> Box<AdblockEngine>;
        /// An engine from `serialize`'s bytes; `ok` false on a version or
        /// checksum mismatch (the caller rebuilds from text).
        fn deserialize_engine(data: &[u8], resources_json: &str, ok: &mut bool)
            -> Box<AdblockEngine>;
        fn serialize(self: &AdblockEngine) -> Vec<u8>;
        fn check_request(
            self: &AdblockEngine,
            url: &str,
            source_url: &str,
            request_type: &str,
            method: &str,
        ) -> NetworkMatch;
        fn csp_directives(self: &AdblockEngine, url: &str, source_url: &str) -> String;
        fn cosmetic_resources(self: &AdblockEngine, url: &str) -> CosmeticResources;
        fn hidden_class_id_selectors(
            self: &AdblockEngine,
            classes: &[String],
            ids: &[String],
            exceptions: &[String],
        ) -> Vec<String>;
    }
}

pub struct AdblockEngine {
    engine: Engine,
}

struct ChromiumDomainResolver;

impl ResolvesDomain for ChromiumDomainResolver {
    fn get_host_domain(&self, host: &str) -> (usize, usize) {
        let (mut start, mut end) = (0usize, host.len());
        ffi::HostDomainRange(host, &mut start, &mut end);
        if start > end || end > host.len() {
            return (0, host.len());
        }
        (start, end)
    }
}

fn install_domain_resolver() {
    // Err means one is installed already: fine, it is this one.
    let _ = adblock::url_parser::set_domain_resolver(Box::new(ChromiumDomainResolver));
}

fn load_resources(engine: &mut Engine, resources_json: &str) {
    if resources_json.is_empty() {
        return;
    }
    match serde_json::from_str::<Vec<Resource>>(resources_json) {
        Ok(resources) => engine.use_resources(resources),
        Err(_) => {}
    }
}

fn new_engine(lists: &[ffi::ListInput], resources_json: &str) -> Box<AdblockEngine> {
    install_domain_resolver();
    let mut set = FilterSet::new(false);
    for list in lists {
        let opts = ParseOptions {
            format: if list.hosts { FilterFormat::Hosts } else { FilterFormat::Standard },
            // uBO's trusted scriptlets carry permission bit 0 in adblock-rust.
            permissions: PermissionMask::from_bits(if list.trusted { 0b1 } else { 0 }),
            ..ParseOptions::default()
        };
        set.add_filter_list(list.text.clone(), opts);
    }
    let mut engine = Engine::new_with_filter_set(set);
    load_resources(&mut engine, resources_json);
    Box::new(AdblockEngine { engine })
}

fn deserialize_engine(data: &[u8], resources_json: &str, ok: &mut bool) -> Box<AdblockEngine> {
    install_domain_resolver();
    let mut engine = Engine::new_with_filter_set(FilterSet::new(false));
    *ok = engine.deserialize(data).is_ok();
    if *ok {
        load_resources(&mut engine, resources_json);
    }
    Box::new(AdblockEngine { engine })
}

impl AdblockEngine {
    fn serialize(&self) -> Vec<u8> {
        self.engine.serialize()
    }

    fn check_request(
        &self,
        url: &str,
        source_url: &str,
        request_type: &str,
        method: &str,
    ) -> ffi::NetworkMatch {
        let mut result = ffi::NetworkMatch {
            block: false,
            exception: false,
            redirect: String::new(),
            rewritten_url: String::new(),
        };
        let Ok(request) = Request::new(url, source_url, request_type, method) else {
            return result;
        };
        let matched = self.engine.check_network_request(&request);
        result.block = matched.should_block();
        result.exception = matched.exception.is_some();
        if let Some(redirect) = matched.redirect {
            result.redirect = redirect;
        }
        if let Some(rewritten) = matched.rewritten_url {
            result.rewritten_url = rewritten;
        }
        result
    }

    fn csp_directives(&self, url: &str, source_url: &str) -> String {
        let Ok(request) = Request::new(url, source_url, "document", "GET") else {
            return String::new();
        };
        self.engine.get_csp_directives(&request).unwrap_or_default()
    }

    fn cosmetic_resources(&self, url: &str) -> ffi::CosmeticResources {
        let resources = self.engine.url_cosmetic_resources(url);
        let mut hide: Vec<String> = resources.hide_selectors.into_iter().collect();
        hide.sort();
        let mut procedural: Vec<String> = resources.procedural_actions.into_iter().collect();
        procedural.sort();
        let mut exceptions: Vec<String> = resources.exceptions.into_iter().collect();
        exceptions.sort();
        ffi::CosmeticResources {
            hide_selectors: hide,
            procedural_actions: procedural,
            exceptions,
            injected_script: resources.injected_script,
            generichide: resources.generichide,
        }
    }

    fn hidden_class_id_selectors(
        &self,
        classes: &[String],
        ids: &[String],
        exceptions: &[String],
    ) -> Vec<String> {
        let exceptions: HashSet<String> = exceptions.iter().cloned().collect();
        self.engine.hidden_class_id_selectors(classes, ids, &exceptions)
    }
}
