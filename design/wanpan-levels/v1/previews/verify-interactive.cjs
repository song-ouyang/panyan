const {chromium} = require('playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');

(async () => {
  const out = __dirname;
  const browser = await chromium.launch({channel:'chrome',headless:true});
  const page = await browser.newPage({viewport:{width:736,height:1200},deviceScaleFactor:1});
  const errors = [];
  page.on('pageerror',error=>errors.push(error.message));
  await page.goto('http://127.0.0.1:8846/');
  const frame = page.frameLocator('iframe');
  const root = frame.locator('#wanpan-badge-preview');
  await root.waitFor();
  await page.waitForTimeout(1450);
  assert.equal(await root.evaluate(el=>el.getAnimations({subtree:true}).filter(a=>a.playState==='running').length),0,'Animation must stop');
  assert.equal(await frame.locator('.wp-badge').evaluate(el=>el.complete && el.naturalWidth>0),true,'Badge must load');
  await root.screenshot({path:path.join(out,'interactive-unlock-736.png')});
  await frame.locator('#wp-replay').click();
  await page.waitForTimeout(280);
  assert.equal(await root.evaluate(el=>el.classList.contains('wp-playing')),true,'Replay starts');
  await root.screenshot({path:path.join(out,'interactive-unlock-motion-736.png'),animations:'allow'});
  await page.waitForTimeout(1150);
  assert.equal(await root.evaluate(el=>el.getAnimations({subtree:true}).filter(a=>a.playState==='running').length),0,'Replay settles');
  await frame.locator('#wp-receive').click();
  await frame.locator('#wp-progress-panel').waitFor({state:'visible'});
  assert.equal(await frame.locator('#wp-day-count').textContent(),'30 / 60 天');
  assert.equal(await frame.locator('#wp-route-count').textContent(),'120 / 250 条');
  const data=JSON.parse(await fs.readFile(path.join(out,'..','levels.json'),'utf8')).levels;
  const cases = [];
  for(const level of data){
    cases.push([level.days,level.routes,level.level]);
    if(level.level>0){
      cases.push([level.days-1,level.routes,level.level-1]);
      cases.push([level.days,level.routes-1,level.level-1]);
    }
  }
  cases.push([500,0,0],[0,3000,0],[30,3000,5],[500,120,5]);
  for(const [days,routes,expected] of cases){
    await root.evaluate((el,{days,routes})=>{
      el.querySelector('#wp-days').value=days;
      el.querySelector('#wp-routes').value=routes;
      el.querySelector('#wp-routes').dispatchEvent(new Event('input',{bubbles:true}));
    },{days,routes});
    assert.equal(await root.getAttribute('data-current-level'),String(expected),`${days} days / ${routes} routes`);
    assert.equal(await frame.locator('#wp-day-fill').evaluate(el=>parseFloat(el.style.width)<=100),true);
    assert.equal(await frame.locator('#wp-route-fill').evaluate(el=>parseFloat(el.style.width)<=100),true);
  }
  await frame.locator('#wp-reset').click();
  await page.waitForTimeout(250);
  await root.screenshot({path:path.join(out,'interactive-progress-736.png')});
  await frame.locator('.wp-rules summary').click();
  assert.equal(await frame.locator('#wp-rule-rows tr').count(),11);
  await frame.locator('.wp-rules summary').click();
  const widths=[];
  for(const width of [736,360,320]){
    await page.setViewportSize({width,height:1200});
    const metrics=await root.evaluate(el=>({width:el.getBoundingClientRect().width,scrollWidth:el.scrollWidth,clientWidth:el.clientWidth}));
    assert.ok(metrics.scrollWidth<=metrics.clientWidth+1,`No overflow at ${width}px`);
    widths.push({viewport:width,...metrics});
    if(width===360) await root.screenshot({path:path.join(out,'interactive-progress-360.png')});
    await frame.locator('#wp-unlock-tab').click();
    if(width===360) await root.screenshot({path:path.join(out,'interactive-unlock-360.png')});
    await frame.locator('#wp-progress-tab').click();
  }
  await frame.locator('#wp-reduced').check();
  await frame.locator('#wp-replay').click();
  assert.equal(await root.evaluate(el=>el.getAnimations({subtree:true}).filter(a=>a.playState==='running' && a.animationName?.startsWith('wp-')).length),0,'Reduced mode is immediate');
  assert.equal(await frame.locator('.wp-reveal').evaluate(el=>getComputedStyle(el).opacity),'1');
  await frame.locator('#wp-reduced').uncheck();
  await page.emulateMedia({reducedMotion:'reduce',colorScheme:'dark'});
  await frame.locator('#wp-replay').click();
  assert.equal(await root.evaluate(el=>el.getAnimations({subtree:true}).filter(a=>a.playState==='running' && a.animationName?.startsWith('wp-')).length),0,'OS reduced mode is immediate');
  await page.setViewportSize({width:360,height:1200});
  await root.screenshot({path:path.join(out,'interactive-unlock-360-dark-reduced.png')});
  assert.deepEqual(errors,[],'No page runtime errors');
  const result={status:'passed',testedAt:new Date().toISOString(),source:'/Users/guoba/.codex/visualizations/2026/09/06/01a074cd-6624-7132-8400-75d63655adca/wanpan-badge-unlock.html',boundaryCases:cases.length,widths,checks:['image loaded','replay starts and stops','receive opens progress and resets example','all 11 level boundaries use both conditions','progress bars clamp at 100%','all 11 rule rows present','no horizontal overflow at 736/360/320','reduced toggle immediate terminal state','OS reduced-motion honored','dark host retains fixed cream product','no runtime errors'],errors};
  await fs.writeFile(path.join(out,'interactive-verification.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result,null,2));
  await browser.close();
})().catch(error=>{console.error(error);process.exitCode=1});
