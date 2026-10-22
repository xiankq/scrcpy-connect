#include "media_codec.h"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <mutex>
#include <thread>
namespace {
mc_sink_v1 sink{};
std::atomic<bool> attached{false},callback_blocked{false},allow_callback{true};
std::atomic<int64_t> accepted{-1};
std::atomic<size_t> callbacks{0};
std::mutex mutex;
std::condition_variable wake;
void check(bool condition,const char* message){if(!condition){std::cerr<<message<<"\n";std::abort();}}
int32_t attach(const uint8_t*,size_t,uint64_t,const mc_sink_v1* value){sink=*value;attached=true;return 0;}
int32_t detach(const uint8_t*,size_t,uint64_t){attached=false;return 0;}
int64_t pcm(void*,const uint8_t*,size_t length){
  callbacks++;
  if(!allow_callback){std::unique_lock<std::mutex> lock(mutex);callback_blocked=true;wake.notify_all();wake.wait(lock,[]{return allow_callback.load();});}
  int64_t amount=accepted.load();return amount==-2?static_cast<int64_t>(length):amount;
}
int send(size_t length,uint64_t generation=7){uint8_t bytes[16]{};return sink.event(sink.context,2,generation,100,0,0,bytes,length,1000,0);}
mc_status status(mc_decoder* decoder){mc_status value{};mc_get_status(decoder,&value);return value;}
template<class P>void until(P predicate){auto end=std::chrono::steady_clock::now()+std::chrono::seconds(2);while(!predicate()){check(std::chrono::steady_clock::now()<end,"timed out");std::this_thread::sleep_for(std::chrono::milliseconds(1));}}
}
int main(){
  mc_config config{};config.struct_size=sizeof(config);config.codec=100;config.generation=7;config.pcm=pcm;
  mc_decoder* decoder=mc_create(&config);check(decoder,"create failed");
  check(mc_attach(decoder,"test",reinterpret_cast<uintptr_t>(&attach),reinterpret_cast<uintptr_t>(&detach))==0,"attach failed");
  check(!status(decoder).native_ready,"ready before output");
  check(send(4,6)<0,"stale generation accepted");
  accepted=0;check(send(4)==0,"packet rejected");until([]{return callbacks.load()>=1;});
  check(!status(decoder).native_ready && !status(decoder).bytes_written,"queued bytes reported as output");
  accepted=-2;check(send(8)==0,"packet rejected");until([&]{return status(decoder).bytes_written==8;});
  check(status(decoder).native_ready,"device accepted bytes but not ready");
  accepted=-1;check(send(4)==0,"packet rejected");until([&]{return status(decoder).error_code<0;});
  check(status(decoder).bytes_written==8,"failed output counted");
  mc_set_paused(decoder,1);size_t before=callbacks.load();check(send(4)==0,"paused packet rejected");std::this_thread::sleep_for(std::chrono::milliseconds(10));check(callbacks.load()==before,"paused audio played");
  mc_set_paused(decoder,0);accepted=-2;allow_callback=false;check(send(4)==0,"packet rejected");until([]{return callback_blocked.load();});
  for(int i=0;i<8;++i)check(send(4)==0,"queue rejected before bound");
  check(send(4)==1,"unbounded packet queue");
  allow_callback=true;wake.notify_all();until([&]{return status(decoder).bytes_written==44;});
  mc_destroy(decoder);check(!attached,"destroy did not detach");
  std::cout<<"media_codec core lifecycle and output accounting passed\n";
}
