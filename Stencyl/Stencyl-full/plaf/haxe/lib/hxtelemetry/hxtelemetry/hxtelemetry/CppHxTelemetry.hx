package hxtelemetry;

#if cpp

import haxe.io.Bytes;

// Static extension for CPP platform.
//
//  public inline static function validate_config(hxt:HxTelemetry):Void
//  public inline static function start_profiler(hxt:HxTelemetry):Int
//  public inline static function disable_alloc_tracking(disabled:Bool):Void
//  public static function do_advance_frame(hxt:HxTelemetry):Void
//  public static function dump_telemetry_frame(thread_num:Int,
//                                              output:haxe.io.Output,
//                                              write_object:Dynamic->Void) {}

class CppHxTelemetry
{

  public inline static function validate_config(hxt:HxTelemetry):Void
  {
    // allocation tracking depends on profiler (probably true for all platforms)
    if (hxt._config.allocations && !hxt._config.profiler) {
      throw "HxTelemetry config.allocations requires config.profiler";
    }

    // Error messages wrt compiler defines
    if (hxt._config.profiler) {
#if !HXCPP_STACK_TRACE
#if openfl
      throw "Using the HXTelemetry Profiler requires -D HXCPP_STACK_TRACE, add to your project.xml: <haxedef name=\"HXCPP_STACK_TRACE\" />";
#else
      throw "Using the HXTelemetry Profiler requires -D HXCPP_STACK_TRACE";
#end
#end
    }
  }

  public inline static function start_profiler(hxt:HxTelemetry):Int
  {
    // __hxcpp_hxt_start_telemetry(is_profiling_enabled:Bool,
    //                             is_allocations_enabled:Bool):Int

    return untyped __global__.__hxcpp_hxt_start_telemetry(hxt._config.profiler,
                                                          hxt._config.allocations);
  }

  public static function do_advance_frame(hxt:HxTelemetry):Void
  {
    disable_alloc_tracking(true);
    if (hxt._config.profiler) {
      untyped __global__.__hxcpp_hxt_stash_telemetry();
    }
    hxt._writer.sendMessage({"dump":true, "thread_num":hxt._thread_num});

    // TODO: support other names, reserved, etc
    var gctotal:Int = Std.int((untyped __global__.__hxcpp_gc_reserved_bytes())/1024);
    var gcused:Int = Std.int((untyped __global__.__hxcpp_gc_used_bytes())/1024);

    if (hxt._last_gctotal != gctotal) {
      hxt._last_gctotal = gctotal;
      hxt._writer.sendMessage({"name":".mem.total","value":gctotal });
    }
    if (hxt._last_gcused != gcused) {
      hxt._last_gcused = gcused;
      hxt._writer.sendMessage({"name":".mem.used","value":gcused });
    }

    // var gctime:Int = untyped __global__.__hxcpp_hxt_dump_gctime();
    // if (gctime>0) {
    //   hxt._writer.sendMessage({"name":Timing.GC,"delta":gctime,"span":gctime});
    // }

    disable_alloc_tracking(false);
  }

  public inline static function disable_alloc_tracking(set_disabled:Bool):Void
  {
    untyped __global__.__hxcpp_hxt_ignore_allocs(set_disabled ? 1 : -1);
  }

  @:functionCode('
//printf("Dumping telemetry from thread %d\\n", thread_num);
TelemetryFrame* frame = __hxcpp_hxt_dump_telemetry(thread_num);
//printf("Num samples %d\\n", frame->samples->size());

// printf("Dumped telemetry, samples=%d, names=%d, allocs=%d, collections=%d\\n",
//         frame->samples->size(),
//         frame->names->size(),
//         frame->allocations->size(),
//   			frame->collections->size());

if (frame==0 || output==null()) return null();

int i=0;
int size;
if (frame->samples!=0) {

  // Write names
  if (frame->names->size()>0) {
    output->writeByte(10);
    output->writeInt32(frame->names->size());
    i = 0;
    size = frame->names->size();
    while (i<size) {
      String s = String(frame->names->at(i++));
      output->writeInt32(s.length);
      output->writeString(s);
    }
  }

  // Write samples
  if (frame->samples->size()>0) {
    output->writeByte(11);
    output->writeInt32(frame->samples->size());
    i = 0;
    size = frame->samples->size();
    while (i<size) {
      output->writeInt32(frame->samples->at(i++));
    }
  }

}

if (frame->allocation_data!=0) {

  // Write stacks
  if (frame->stacks->size()>0) {
    output->writeByte(12);
    output->writeInt32(frame->stacks->size());
    i = 0;
    size = frame->stacks->size();
    while (i<size) {
			output->writeInt32(frame->stacks->at(i++));
		}
  }

  // Write allocations
  if (frame->allocation_data->size()>0) {
    // printf(\" -- writing allocs: %d\\n\", frame->allocation_data->size());
    output->writeByte(13);
    output->writeInt32(frame->allocation_data->size());
    i = 0;
    size = frame->allocation_data->size();

    if (size>0) {
  		::haxe::io::Bytes bytes = ::haxe::io::Bytes_obj::alloc((int)size*4);

      while (i<size) {
      //  output->writeInt32(frame->allocation_data->at(i++));
        int d = frame->allocation_data->at(i);
  			bytes->b[(int)i*4]   = d>>24;
				bytes->b[(int)i*4+1] = d>>16;
				bytes->b[(int)i*4+2] = d>>8;
				bytes->b[(int)i*4+3] = d;
        i++;
      }
      output->writeFullBytes(bytes, 0, size*4);
		}
  }
}

// GC time
hx::Anon gct = hx::Anon_obj::Create();
gct->Add(HX_CSTRING("name") , HX_CSTRING(".gc"),false);
gct->Add(HX_CSTRING("delta") , (int)frame->gctime,false);
gct->Add(HX_CSTRING("span") , (int)frame->gctime,false);
write_object(gct);

')
  public static function dump_telemetry_frame(thread_num:Int,
                                              output:haxe.io.Output,
                                              write_object:Dynamic->Void) {}

  public static function compile_fails_without_this_function_definition():Void
  {
    // DCE? seems to need this for the cpp code above...
    var b:Bytes = Bytes.alloc(4);
  }
}

#end
