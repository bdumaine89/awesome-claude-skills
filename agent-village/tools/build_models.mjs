#!/usr/bin/env node
// Build the 3D village assets from two free CC0 KayKit packs by Kay Lousberg.
//
//   git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 hex
//   git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 chars
//   cd tools && npm install && node build_models.mjs --hex ../path/hex --chars ../path/chars
//
// Writes (all committed; the app needs nothing at runtime):
//   static/models/hex/*.gltf|.bin + hexagons_medieval.png   tiles, buildings, nature, props
//   static/models/chars/<villager>.glb                       characters, trimmed to the animations we use
//   static/vendor/three/...                                  Three.js r170 (MIT) + the addons we import
//   static/models/CREDITS.md
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { NodeIO } from "@gltf-transform/core";
import { prune, dedup } from "@gltf-transform/functions";

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(here, "..");
const arg = (k) => { const i = process.argv.indexOf(k); if (i < 0) throw new Error(`missing ${k}`); return path.resolve(process.argv[i + 1]); };
const HEX = path.join(arg("--hex"), "addons/kaykit_medieval_hexagon_pack/Assets/gltf");
const CHARS = path.join(arg("--chars"), "addons/kaykit_character_pack_adventures/Characters/gltf");
const OUT = path.join(ROOT, "static/models");

// --------------------------------------------------------------- village
const MODELS = [
  ...["hex_grass", "hex_water"].map((n) => `tiles/base/${n}`),
  ..."ABCDEFGHIJKLM".split("").map((c) => `tiles/roads/hex_road_${c}`),
  "buildings/blue/building_church_blue", "buildings/blue/building_tower_A_blue", "buildings/red/building_market_red",
  "buildings/blue/building_well_blue", "buildings/red/building_home_A_red", "buildings/yellow/building_home_B_yellow",
  "buildings/green/building_home_A_green", "buildings/blue/building_home_B_blue", "buildings/red/building_tavern_red",
  "buildings/yellow/building_blacksmith_yellow", "buildings/yellow/building_windmill_yellow",
  "buildings/green/building_watermill_green", "buildings/blue/building_lumbermill_blue", "buildings/neutral/building_grain",
  "buildings/neutral/fence_wood_straight", "buildings/neutral/building_stage_A",
  ...["trees_A_large", "trees_A_medium", "trees_A_small", "trees_B_large", "trees_B_medium", "trees_B_small",
    "tree_single_A", "tree_single_B", "rock_single_A", "rock_single_B", "rock_single_C", "rock_single_D",
    "hills_A_trees", "hills_B_trees", "hills_C", "mountain_A_grass_trees", "mountain_B_grass", "mountain_C_grass_trees",
    "cloud_big", "cloud_small", "waterlily_A", "waterlily_B", "waterplant_A", "waterplant_B"].map((n) => `decoration/nature/${n}`),
  ...["barrel", "crate_A_big", "crate_B_small", "sack", "wheelbarrow", "tent", "flag_red", "flag_blue",
    "bucket_water", "resource_lumber", "crate_open", "pallet"].map((n) => `decoration/props/${n}`),
];

// villager id -> source character, animations kept
const VILLAGERS = { ada: "Knight", leo: "Rogue", maya: "Mage" };
const ANIMS = ["Idle", "Walking_A", "Interact", "Use_Item", "Spellcasting", "Cheer", "Sit_Floor_Idle", "Lie_Idle", "PickUp"];

function copyVillage() {
  const dst = path.join(OUT, "hex");
  fs.mkdirSync(dst, { recursive: true });
  for (const m of MODELS) {
    const name = path.basename(m);
    const gltf = JSON.parse(fs.readFileSync(path.join(HEX, m + ".gltf"), "utf8"));
    fs.copyFileSync(path.join(HEX, m + ".bin"), path.join(dst, name + ".bin"));
    gltf.buffers[0].uri = name + ".bin";
    (gltf.images || []).forEach((im) => (im.uri = "hexagons_medieval.png"));
    fs.writeFileSync(path.join(dst, name + ".gltf"), JSON.stringify(gltf));
  }
  fs.copyFileSync(path.join(HEX, "tiles/base/hexagons_medieval.png"), path.join(dst, "hexagons_medieval.png"));
  console.log("village models", MODELS.length);
}

async function buildCharacters() {
  const io = new NodeIO();
  fs.mkdirSync(path.join(OUT, "chars"), { recursive: true });
  for (const [id, src] of Object.entries(VILLAGERS)) {
    const doc = await io.read(path.join(CHARS, `${src}.glb`));
    const root = doc.getRoot();
    for (const a of root.listAnimations()) if (!ANIMS.includes(a.getName())) a.dispose();
    // drop held weapons/shields: they hang off the hand-slot bones
    for (const node of root.listNodes()) {
      if (/handslot/i.test(node.getName())) for (const child of node.listChildren()) child.dispose();
    }
    await doc.transform(dedup(), prune());
    const out = path.join(OUT, "chars", `${id}.glb`);
    await io.write(out, doc);
    console.log("character", id, `${src}.glb`, (fs.statSync(out).size / 1e6).toFixed(2), "MB");
  }
}

function vendorThree() {
  const three = path.join(here, "node_modules/three");
  const dst = path.join(ROOT, "static/vendor/three");
  const files = ["build/three.module.min.js", "examples/jsm/loaders/GLTFLoader.js", "examples/jsm/utils/BufferGeometryUtils.js",
    "examples/jsm/utils/SkeletonUtils.js", "examples/jsm/controls/OrbitControls.js", "LICENSE"];
  for (const f of files) {
    fs.mkdirSync(path.dirname(path.join(dst, f)), { recursive: true });
    fs.copyFileSync(path.join(three, f), path.join(dst, f));
  }
  console.log("vendored three", JSON.parse(fs.readFileSync(path.join(three, "package.json"))).version);
}

function credits() {
  fs.writeFileSync(path.join(OUT, "CREDITS.md"), `# 3D art credits

All village and character models are by **Kay Lousberg** (https://www.kaylousberg.com), released under
**CC0 1.0** (public domain): free for personal, educational and commercial use, attribution appreciated
but not required.

- KayKit: Medieval Hexagon Pack 1.0: https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0
- KayKit: Adventurers Character Pack 1.0: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0

Changes made by \`tools/build_models.mjs\`: files flattened into one folder sharing a single texture;
characters trimmed to ${ANIMS.length} animations with their weapons removed. Mayor Ada uses the Knight model,
Scout Leo the Rogue, Scribe Maya the Mage.

Rendering uses Three.js r170 (MIT licence, see static/vendor/three/LICENSE).
`);
}

copyVillage();
await buildCharacters();
vendorThree();
credits();
