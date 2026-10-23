// Direct page-target CDP avoids assuming CEF's isolated profiles share one context.
export class NativeTarget {
  constructor(url){
    this.socket=new WebSocket(url);this.next=0;this.pending=new Map();
    this.ready=new Promise((resolve,reject)=>{this.socket.addEventListener('open',resolve,{once:true});this.socket.addEventListener('error',reject,{once:true});});
    this.socket.addEventListener('message',event=>{const message=JSON.parse(event.data);const request=this.pending.get(message.id);if(!request)return;this.pending.delete(message.id);clearTimeout(request.timer);message.error?request.reject(new Error(JSON.stringify(message.error))):request.resolve(message.result);});
    this.socket.addEventListener('close',()=>{for(const request of this.pending.values()){clearTimeout(request.timer);request.reject(new Error('Native target closed'));}this.pending.clear();});
  }
  async send(method,params={}){
    await this.ready;const id=++this.next;
    return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('CDP timeout: '+method));},8000);this.pending.set(id,{resolve,reject,timer});this.socket.send(JSON.stringify({id,method,params}));});
  }
  async evaluate(fn,arg,userGesture=false){
    const response=await this.send('Runtime.evaluate',{expression:`(${fn.toString()})(${JSON.stringify(arg)??''})`,returnByValue:true,awaitPromise:true,userGesture});
    if(response.exceptionDetails)throw new Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }
  close(){this.socket.close();}
}
