import { randomUUID } from 'node:crypto';
import { mkdir, writeFile, rename, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
export async function command(directory, action, values={}) {
  await mkdir(directory,{recursive:true,mode:0o700});
  const id=randomUUID();const file=join(directory,id+'.command.json');
  await writeFile(file+'.tmp',JSON.stringify({action,...values}),{mode:0o600});await rename(file+'.tmp',file);
  const output=join(directory,id+'.result.json');const end=Date.now()+12000;
  while(Date.now()<end){
    try{const reply=JSON.parse(await readFile(output,'utf8'));await unlink(output);return reply;}
    catch(error){if(error.code!=='ENOENT')throw error;await new Promise(resolve=>setTimeout(resolve,30));}
  }
  throw new Error('Native test command timed out: '+action);
}
export async function waitFor(predicate,message){
  const end=Date.now()+15000;
  while(Date.now()<end){if(await predicate())return;await new Promise(resolve=>setTimeout(resolve,60));}
  throw new Error(message);
}
