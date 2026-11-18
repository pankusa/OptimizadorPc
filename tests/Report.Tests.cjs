// npm install --no-save jsdom; node tests/Report.Tests.cjs
// DOM/logic tests, not browser layout, sound or Windows hardware validation.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {JSDOM,VirtualConsole}=require('jsdom');
const root=path.resolve(__dirname,'..'),template=fs.readFileSync(path.join(root,'app/Report.html'),'utf8');
const fixture=JSON.parse(fs.readFileSync(path.join(root,'docs/Ejemplo_datos.json'),'utf8'));
let count=0;const names=[];
function test(name,fn){fn();count++;names.push(name);}
function setup(data,store=new Map(),blocked=false){
 let blob=null;const errors=[];const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(!e.message.includes('navigation'))errors.push(e.message);});
 const html=data===null?template:template.replace('__REPORT_BASE64__',Buffer.from(JSON.stringify(data)).toString('base64'));
 const dom=new JSDOM(html,{runScripts:'dangerously',url:'https://pcclaro.test/report',virtualConsole:vc,beforeParse(w){
  w.TextDecoder=TextDecoder;w.Blob=Blob;w.URL.createObjectURL=b=>{blob=b;return 'blob:test'};w.URL.revokeObjectURL=()=>{};
  w.HTMLAnchorElement.prototype.click=function(){};
  Object.defineProperty(w,'localStorage',{get(){if(blocked)throw Error('Storage blocked');return {getItem:k=>store.get(k)||null,setItem:(k,v)=>store.set(k,v)}}});
  w.alert=msg=>errors.push(msg);w.print=()=>{};w.HTMLElement.prototype.scrollIntoView=function(){};
 }});
 return {dom,w:dom.window,d:dom.window.document,errors,blob:()=>blob,store};
}
function all(s,q){return [...s.d.querySelectorAll(q)]}
function click(s,q){const e=s.d.querySelector(q);assert.ok(e,q);e.click()}
function category(s,name){const b=all(s,'#categories button').find(b=>b.textContent===name);assert.ok(b);b.click()}
function search(s,text){const e=s.d.getElementById('search');e.value=text;e.dispatchEvent(new s.w.Event('input'))}
function attention(s,checked){const e=s.d.getElementById('attention');e.checked=checked;e.dispatchEvent(new s.w.Event('change'))}
(async()=>{
 const s=setup(fixture),n=fixture.checks.length;
 test('21 controles',()=>assert.equal(all(s,'.result').length,21));
 test('12 pruebas guiadas',()=>assert.equal(all(s,'.manualcard').length,12));
 test('ejemplo identificado',()=>assert.match(s.d.querySelector('#main').textContent,/DATOS FICTICIOS/));
 test('recuento de estados consistente',()=>assert.equal(all(s,'.count strong').reduce((a,e)=>a+Number(e.textContent),0),n));
 test('nombre del equipo',()=>assert.match(s.d.getElementById('meta').textContent,/PC-DE-EJEMPLO/));
 category(s,'Almacenamiento');test('filtro de area',()=>assert.equal(all(s,'.result').length,2));
 search(s,'volumenes');test('busqueda de titulo',()=>assert.equal(all(s,'.result').length,1));
 search(s,'imposiblexxxxxxxxxx');test('estado vacio',()=>assert.match(s.d.getElementById('results').textContent,/No hay resultados/));
 search(s,'');category(s,'Todas');attention(s,true);
 test('alertas y pendientes',()=>assert.equal(all(s,'.result').length,fixture.checks.filter(c=>['warn','critical','unknown'].includes(c.status)).length));
 test('filtro excluye inventarios',()=>assert.equal(all(s,'.result[data-status="info"]').length,0));
 attention(s,false);
 test('orden por prioridad',()=>assert.equal(s.d.querySelector('.result').dataset.status,'warn'));
 click(s,'.manualcard .choices button:nth-child(2)');
 test('respuesta seleccionada',()=>assert.equal(s.d.querySelector('.manualcard [aria-pressed="true"]').textContent,'Falla observada'));
 test('respuesta visible en impresion',()=>assert.match(s.d.querySelector('.manualcard').textContent,/Resultado declarado: Falla observada/));
 test('contador manual',()=>assert.match(s.d.getElementById('manualstate').textContent,/1 de 12/));
 const restored=setup(fixture,s.store);
 test('respuestas conservadas entre aperturas',()=>assert.equal(restored.d.querySelector('.manualcard [aria-pressed="true"]').textContent,'Falla observada'));
 click(s,'#export');const exported=JSON.parse(await s.blob().text());
 test('exporta controles',()=>assert.equal(exported.checks.length,21));
 test('exporta pruebas pendientes y respondidas',()=>assert.equal(exported.manual.length,12));
 test('exporta respuesta',()=>assert.equal(exported.manual[0].status,'fail'));
 test('distingue observacion humana',()=>assert.equal(exported.manual[0].source,'observacion_del_usuario'));
 test('conserva fecha de respuesta',()=>assert.ok(exported.manual[0].updatedAt));
 test('no modifica JSON original',()=>assert.equal(fixture.manual.length,0));
 click(s,'#keyboard');
 s.d.getElementById('keys').dispatchEvent(new s.w.KeyboardEvent('keydown',{key:'a',code:'KeyA',bubbles:true,cancelable:true}));
 test('teclado por codigos',()=>assert.match(s.d.getElementById('keys').textContent,/KeyA/));
 test('teclado recibe foco',()=>assert.equal(s.d.activeElement.id,'keys'));
 click(s,'#screen');test('prueba de pantalla abre',()=>assert.equal(s.d.getElementById('overlay').style.display,'flex'));
 click(s,'#overlay');test('color de pantalla avanza',()=>assert.equal(s.d.getElementById('overlay').style.background,'rgb(0, 0, 0)'));
 s.d.dispatchEvent(new s.w.KeyboardEvent('keydown',{key:'Escape'}));test('Escape cierra prueba',()=>assert.equal(s.d.getElementById('overlay').style.display,'none'));
 category(s,'Hardware');search(s,'RAM');const previous=all(s,'.result').length;
 s.w.dispatchEvent(new s.w.Event('beforeprint'));
 test('imprime todas las areas aunque exista filtro',()=>assert.equal(all(s,'.result').length,21));
 test('imprime detalle completo',()=>assert.equal(all(s,'.result[open]').length,21));
 s.w.dispatchEvent(new s.w.Event('beforeprint'));s.w.dispatchEvent(new s.w.Event('afterprint'));
 test('restaura filtro despues de imprimir',()=>assert.equal(all(s,'.result').length,previous));
 test('restaura busqueda despues de imprimir',()=>assert.equal(s.d.getElementById('search').value,'RAM'));
 test('sin errores JS en flujo principal',()=>assert.deepEqual(s.errors,[]));
 const xss=structuredClone(fixture);xss.checks.push({id:'xss',category:'Equipo',title:'<img src=x onerror="window.pwned=1">',summary:'</script><script>window.pwned=2</script>',status:'unknown',scope:'Test',next:'Texto literal',rows:[{Valor:'<svg onload=window.pwned=3>'}],error:'<script>window.pwned=4</script>'});
 const secure=setup(xss);
 test('datos HTML no ejecutan codigo',()=>assert.equal(secure.w.pwned,undefined));
 search(secure,'onerror');test('titulo con HTML se muestra literal',()=>assert.equal(secure.d.querySelector('.result h3').textContent,xss.checks.at(-1).title));
 test('no crea elementos inyectados',()=>assert.equal(all(secure,'.result img,.result svg,.result script').length,0));
 test('error tecnico es texto literal',()=>assert.equal(secure.d.querySelector('.technical').textContent,'Detalle técnico: '+xss.checks.at(-1).error));
 test('sin scripts remotos',()=>assert.equal(all(secure,'script[src]').length,0));
 test('sin CSS remoto',()=>assert.equal(all(secure,'link[rel="stylesheet"]').length,0));
 const blocked=setup(fixture,new Map(),true);click(blocked,'.manualcard .choices button');
 test('pruebas manuales funcionan sin almacenamiento',()=>assert.equal(blocked.d.querySelector('.manualcard [aria-pressed="true"]').textContent,'Correcto'));
 test('avisa cuando no puede conservar respuestas',()=>assert.match(blocked.d.getElementById('manualstate').textContent,/no permite guardarlas/));
 const empty=setup(null);test('plantilla sin datos muestra error claro',()=>assert.match(empty.d.getElementById('main').textContent,/No se pudo abrir el informe/));
 const invalid=structuredClone(fixture);invalid.schemaVersion=99;
 test('rechaza esquema incompatible',()=>assert.match(setup(invalid).d.getElementById('main').textContent,/No se pudo abrir el informe/));
 const safe=structuredClone(fixture);safe.checks=safe.checks.filter(x=>!['warn','critical'].includes(x.status));
 test('sin alertas conserva pendientes visibles',()=>assert.match(setup(safe).d.getElementById('priorities').textContent,/completá las pruebas guiadas/));
 if(process.env.PCCLARO_SNAPSHOT){category(s,'Todas');search(s,'');fs.writeFileSync(process.env.PCCLARO_SNAPSHOT,s.dom.serialize());}
 console.log(JSON.stringify({passed:count,environment:'Node.js + jsdom; sin motor de layout ni hardware Windows',checks:names},null,2));
 for(const c of [s,restored,secure,blocked,empty])c.w.close();
})().catch(e=>{console.error(e);process.exit(1)});
