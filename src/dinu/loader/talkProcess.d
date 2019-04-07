module dinu.loader.talkProcess;


import dinu;


__gshared:


class TalkProcessLoader: ChoiceLoader {

	override void run(){
		foreach(d; "/proc".dirContent){
			try {
				if((getAttributes(d) & S_IRUSR) && d.isDir && (d ~ "/comm").exists && d.chompPrefix("/proc/").isNumeric){
					add(new immutable CommandTalkProcess(d.chompPrefix("/proc/").to!size_t, (d ~ "/comm").read.to!string.strip));
				}
			}catch(FileException){}
		}
	}

}
