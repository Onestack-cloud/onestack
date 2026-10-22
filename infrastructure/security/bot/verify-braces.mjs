import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const braces = require('braces');
assert.equal(require('braces/package.json').version, '3.0.3', 'Review and retire the backport when upstream changes');

const rejectDepth = error => error instanceof SyntaxError && error.message === 'Brace pattern exceeds security depth or node limit';
for (const depth of [500, 2000, 4000]) {
  const pattern = '{'.repeat(depth) + 'x,y' + '}'.repeat(depth);
  for (const operation of [braces, braces.parse, braces.compile, braces.expand, braces.stringify]) {
    assert.throws(() => operation(pattern), rejectDepth);
  }
}
const cyclic = {type:'root', nodes:[]};
cyclic.nodes.push(cyclic);
for (const operation of [braces.compile, braces.expand, braces.stringify]) {
  assert.throws(() => operation(cyclic), rejectDepth);
}
assert.equal(braces.compile('a/{b,c}/d'), 'a/(b|c)/d');
assert.deepEqual(braces.expand('a/{b,c}/{1..3}'), ['a/b/1','a/b/2','a/b/3','a/c/1','a/c/2','a/c/3']);
assert.equal(braces.stringify(braces.parse('café/{one,two}')), 'café/{one,two}');
assert.deepEqual(braces(['{a,b}', '{1..2}'], {expand:true}), ['a','b','1','2']);
for (let depth = 1; depth <= 60; depth++) {
  assert.doesNotThrow(() => braces.compile('{'.repeat(depth) + 'a,b' + '}'.repeat(depth)));
}
console.log(JSON.stringify({mitigated:'GHSA-vfj7-8cjw-p6xm', version:'3.0.3', checks:'deep strings, cyclic AST and valid pattern compatibility'}));
