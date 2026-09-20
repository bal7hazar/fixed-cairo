//! `refgen`: golden-vector generator. glam-rs (f64) is the oracle of the Cairo port.
//!
//! ```text
//! cargo run --manifest-path tools/refgen/Cargo.toml -- gen [module...]    # write the files
//! cargo run --manifest-path tools/refgen/Cargo.toml -- check [module...]  # CI: exit 1 on drift
//! cargo run --manifest-path tools/refgen/Cargo.toml -- list               # specs and oracles
//! ```

mod cases;
mod domain;
mod emit;
mod oracles;
mod registry;
mod rng;
mod spec;
mod types;
mod value;

/// What an oracle file needs: `use crate::prelude::*;`.
#[allow(unused_imports)]
pub mod prelude {
    pub use crate::domain::value_of;
    pub use crate::registry::Registry;
    pub use crate::rng::Rng;
    pub use crate::types::Ty;
    pub use crate::value::{quantize, raw_to_f64, skip, Out, Value, FRAC_BITS, ONE_F64, ONE_RAW};
    pub use glam::{
        BVec2, BVec3, BVec4, DAffine2, DAffine3, DMat2, DMat3, DMat4, DQuat, DVec2, DVec3, DVec4,
        EulerRot, IVec2, IVec3, IVec4, UVec2, UVec3, UVec4,
    };
}

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::{env, fs};

use registry::Registries;
use spec::Spec;

const USAGE: &str =
    "usage: refgen [--root <repo>] [--specs <dir>] [--all] <gen|check|list> [module...]";

fn default_specs_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("specs")
}

fn default_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..")
}

/// Loads the specs, sorted by module name; `filter` empty = all.
fn load_specs(dir: &Path, filter: &[String]) -> Result<Vec<Spec>, String> {
    let mut paths: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    paths.sort();
    let specs: Result<Vec<Spec>, String> = paths.iter().map(|p| Spec::load(p)).collect();
    let mut specs = specs?;
    for module in filter {
        if !specs.iter().any(|s| &s.module == module) {
            return Err(format!("no spec {}/{module}.toml", dir.display()));
        }
    }
    if !filter.is_empty() {
        specs.retain(|s| filter.contains(&s.module));
    }
    Ok(specs)
}

fn target(root: &Path, spec: &Spec) -> PathBuf {
    root.join("packages")
        .join(&spec.package)
        .join("tests")
        .join(format!("golden_{}.cairo", spec.module))
}

fn run() -> Result<bool, String> {
    let mut args: Vec<String> = env::args().skip(1).collect();
    let mut root = default_root();
    let mut specs_dir = default_specs_dir();
    let mut all = false;
    loop {
        match args.first().map(String::as_str) {
            // Alternative spec directory (tests of the generator itself).
            Some("--specs") if args.len() >= 2 => {
                specs_dir = PathBuf::from(args[1].clone());
                args.drain(..2);
            }
            Some("--root") if args.len() >= 2 => {
                root = PathBuf::from(args[1].clone());
                args.drain(..2);
            }
            // Preview: ignore every `enabled = false` (never use it for committed files).
            Some("--all") => {
                all = true;
                args.remove(0);
            }
            _ => break,
        }
    }
    let Some(command) = args.first().cloned() else {
        return Err(USAGE.into());
    };
    let modules = &args[1..];

    let mut registries = Registries::default();
    oracles::register_all(&mut registries);
    let mut specs = load_specs(&specs_dir, modules)?;
    if all {
        for spec in &mut specs {
            spec.enabled = true;
            spec.functions.iter_mut().for_each(|f| f.enabled = true);
        }
    }

    match command.as_str() {
        "gen" | "check" => {
            let mut clean = true;
            for spec in &specs {
                let text = emit::module(spec, registries.get(&spec.module))
                    .map_err(|e| format!("specs/{}.toml: {e}", spec.module))?;
                let path = target(&root, spec);
                // Tolerate CRLF checkouts.
                let current = fs::read_to_string(&path)
                    .ok()
                    .map(|t| t.replace("\r\n", "\n"));
                let up_to_date = current.as_deref() == Some(text.as_str());
                let shown = path
                    .strip_prefix(&root)
                    .unwrap_or(&path)
                    .display()
                    .to_string();
                if command == "gen" {
                    if !path.exists() {
                        return Err(format!(
                            "{shown} does not exist: golden files are pre-declared stubs, check \
                             `module` and `package`"
                        ));
                    }
                    if !up_to_date {
                        fs::write(&path, &text).map_err(|e| format!("{shown}: {e}"))?;
                    }
                    println!(
                        "{} {shown}",
                        if up_to_date { "unchanged" } else { "wrote    " }
                    );
                } else if up_to_date {
                    println!("ok    {shown}");
                } else {
                    clean = false;
                    println!("STALE {shown}");
                }
            }
            if !clean {
                eprintln!(
                    "golden files differ from the generator output; run:\n  cargo run \
                     --manifest-path tools/refgen/Cargo.toml -- gen"
                );
            }
            Ok(clean)
        }
        "list" => {
            for spec in &specs {
                let registry = registries.get(&spec.module);
                let state = if spec.enabled {
                    ""
                } else {
                    " [module disabled]"
                };
                println!("{} (package {}){state}", spec.module, spec.package);
                for f in &spec.functions {
                    let oracle = f.oracle.as_deref().unwrap_or(&f.name);
                    let has_oracle = registry.is_some_and(|r| r.oracles.contains_key(oracle));
                    println!(
                        "  {:<8} {:<24} tol {:<3} {}",
                        if f.enabled { "enabled" } else { "disabled" },
                        f.name,
                        f.tolerance,
                        if has_oracle { "" } else { "(no oracle yet)" }
                    );
                }
                if let Some(registry) = registry {
                    let used: Vec<&str> = spec
                        .functions
                        .iter()
                        .map(|f| f.oracle.as_deref().unwrap_or(&f.name))
                        .collect();
                    for name in registry
                        .oracles
                        .keys()
                        .filter(|n| !used.contains(&n.as_str()))
                    {
                        println!("  oracle without spec entry: {name}");
                    }
                }
            }
            Ok(true)
        }
        _ => Err(USAGE.into()),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(2)
        }
    }
}
