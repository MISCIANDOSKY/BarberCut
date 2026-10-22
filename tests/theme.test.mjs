import test from "node:test";
import assert from "node:assert/strict";
import { readTheme, applyTheme, THEME_STORAGE_KEY } from "../src/lib/theme.mjs";
test("Il tema predefinito resta scuro, anche con preferenze non valide o storage bloccato",()=>{
 for(const value of [null,"dark","system","unexpected"]) assert.equal(readTheme({getItem:key=>{assert.equal(key,THEME_STORAGE_KEY);return value;}}),"dark");
 assert.equal(readTheme(),"dark");
 assert.equal(readTheme({getItem(){throw new Error("blocked");}}),"dark");
 assert.equal(readTheme({getItem:()=>"light"}),"light");
});
test("Il cambio aggiorna insieme palette, controlli e colore della barra PWA",()=>{
 const meta={setAttribute(name,value){assert.equal(name,"content");this.content=value;}};
 const doc={documentElement:{dataset:{},style:{}},querySelector(selector){assert.equal(selector,'meta[name="theme-color"]');return meta;}};
 assert.equal(applyTheme("light",doc),"light");
 assert.equal(doc.documentElement.dataset.theme,"light");
 assert.equal(doc.documentElement.style.colorScheme,"light");
 assert.equal(meta.content,"#f7f6f2");
 assert.equal(applyTheme("dark",doc),"dark");
 assert.equal(doc.documentElement.dataset.theme,"dark");
 assert.equal(doc.documentElement.style.colorScheme,"dark");
 assert.equal(meta.content,"#151815");
 assert.equal(applyTheme("unexpected",doc),"dark");
 assert.doesNotThrow(()=>applyTheme("light",{documentElement:{dataset:{},style:{}},querySelector:()=>null}));
});
