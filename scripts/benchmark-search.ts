import { performance } from 'node:perf_hooks';
import { freshState } from '../electron/storage/store';
import { suggestions } from '../shared/suggestions';
const state=freshState();
state.tabs=Array.from({length:500},(_,i)=>({id:`tab-${i}`,spaceId:'personal',profileId:'personal',url:`https://site-${i}.example.com/`,title:`Design reference ${i}`,pinned:false,lastActive:i,loading:false,canGoBack:false,canGoForward:false,status:'discarded'}));
state.history=Array.from({length:2000},(_,i)=>({url:`https://history-${i}.example.com/`,title:`Design notes ${i}`,visitedAt:i}));
const samples:number[]=[];
for(let i=0;i<100;i++){const start=performance.now();suggestions(['d','de','des','design','design n'][i%5],state);samples.push(performance.now()-start);}
samples.sort((a,b)=>a-b);
console.log(JSON.stringify({medianMs:samples[50],p95Ms:samples[95],queries:100,tabs:500,history:2000}));
