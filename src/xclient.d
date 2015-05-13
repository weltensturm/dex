module dinu.xclient;

import
	std.path,
	std.math,
	std.process,
	std.file,
	std.string,
	std.stdio,
	std.conv,
	std.datetime,
	std.algorithm,
	core.thread,
	draw,
	cli,
	dinu.util,
	dinu.window,
	dinu.animation,
	dinu.commandBuilder,
	dinu.command,
	dinu.dinu,
	desktop,
	x11.X,
	x11.Xlib,
	x11.keysymdef;

__gshared:



private double em1;

int em(double mod){
	return cast(int)(round(em1*mod));
}



class XClient: dinu.window.Window {

	dinu.window.Window resultWindow;
	int padding;
	int animationY;
	bool shouldClose;
	long lastDraw;
	double animStart;

	Animation windowAnimation;

	this(){
		super(options.screen, [0, 0], [1,1]);
		dc.initfont(options.font);
		em1 = dc.font.height*1.3;
		resize([
			options.w ? options.w : DisplayWidth(display, screen),
			1.em*(options.lines+1)+0.8.em
		]);
		move([
			options.x,
			-size.h
		]);
		show;
		grabKeyboard;
		padding = 0.4.em;
		lastDraw = Clock.currSystemTick.msecs;
		windowAnimation = new AnimationExpIn(pos.y, 0, 0.1+size.h/4000.0);
	}

	void update(){
		int targetY = cast(int)windowAnimation.calculate;
		if(targetY != pos.y)
			move([pos.x, targetY]);
		else if(windowAnimation.done && shouldClose)
			super.destroy;
	}

	override void draw(){
		if(!active)
			return;
		assert(thread_isMainThread);

		dc.rect([0,0], [size.w, size.h], options.colorBg);
		int separator = size.w/4;
		drawInput([0, options.lines*1.em], [size.w, size.h-1.em*options.lines], separator);
		drawOutput([0, 0], [size.w, 1.em*options.lines], separator);
		super.draw;
	}

	void drawInput(int[2] pos, int[2] size, int sep){
		auto paddingVert = 0.2.em;
		dc.rect([sep, pos.y+paddingVert], [size.w/2, size.h-paddingVert*2], options.colorInputBg);
		// cwd
		int textY = pos.y+size.h/2-0.5.em;
		dc.text([pos.x+sep, textY], getcwd, commandBuilder.commandHistory ? options.colorExec : options.colorHint, 1.4);
		dc.clip([pos.x+size.w/4, pos.y], [size.w/2, size.h]);
		int textWidth = dc.textWidth(commandBuilder.toString ~ "..");
		int offset = -max(0, textWidth-size.w/2);
		int textStart = offset+pos.x+sep+padding;
		// input
		if(!commandBuilder.commandSelected){
			dc.text([textStart, textY], commandBuilder.toString, options.colorInput);
		}else{
			auto xoff = textStart+commandBuilder.commandSelected.draw(dc, [textStart, textY], false);
			foreach(param; commandBuilder.command[1..$])
				xoff += dc.text([xoff, textY], param ~ ' ', options.colorInput);
		}
		// cursor
		int cursorOffset = dc.textWidth(commandBuilder.finishedPart);
		int curpos = padding+offset+pos.x+sep+cursorOffset + dc.textWidth(commandBuilder.text[0..commandBuilder.cursor]);
		dc.rect([curpos, pos.y+paddingVert*2], [1, size.y-paddingVert*4], options.colorInput);
		dc.noclip;
	}

	void showOutput(){
		options.lines = 15;
		int height = 1.em*(options.lines+1)+0.8.em-1;
		XResizeWindow(display, handle, size.w, height);
		XMoveWindow(display, handle, pos.x, pos.y-height+size.h);
		windowAnimation = new AnimationExpIn(pos.y-height+size.h, options.y, 0.1+size.h/4000.0);
	}

	void drawOutput(int[2] pos, int[2] size, int sep){
		dc.rect(pos, size, options.colorOutputBg);
		auto matches = output.dup;
		auto selected = commandBuilder.selected < -1 ? -commandBuilder.selected-2 : -1;
		long start = min(max(0, cast(long)matches.length-cast(long)options.lines), max(0, selected+1-options.lines/2));
		foreach(i, match; matches[start..min($, start+options.lines)]){
			int y = cast(int)(pos.y+size.h - size.h*(i+1)/cast(double)options.lines);
			if(start+i == selected)
				dc.rect([pos.x+sep, y], [size.w/2, 1.em], options.colorHintBg);
			dc.clip([pos.x, pos.y], [size.w/4*3, size.h]);
			match.draw(dc, [pos.x+sep+padding, y], start+i == selected);
			dc.noclip;
		}
	}

	override void destroy(){
		windowAnimation = new AnimationExpOut(pos.y, -size.h, 0.1 + size.h/4000.0);
		shouldClose = true;
		XUngrabKeyboard(display, CurrentTime);
	}

	override void onKey(XKeyEvent* ev){
		char[5] buf;
		KeySym key;
		Status status;
		auto length = Xutf8LookupString(xic, ev, buf.ptr, cast(int)buf.length, &key, &status);
		if(ev.state & ControlMask)
			switch(key){
				case XK_r:
					commandBuilder.commandHistory = true;
					commandBuilder.resetFilter;
					return;
				case XK_q:
					key = XK_Escape;
					break;
				case XK_u:
					commandBuilder.deleteLeft;
					return;
				case XK_BackSpace:
					commandBuilder.deleteWordLeft;
					return;
				case XK_Delete:
					commandBuilder.deleteWordRight;
					return;
				case XK_V:
				case XK_v:
					XConvertSelection(display, clip, utf8, utf8, handle, CurrentTime);
					return;
				default:
					break;
			}
		switch(key){
			case XK_Escape:
				close();
				return;
			case XK_Delete:
				commandBuilder.delChar;
				return;				
			case XK_BackSpace:
				commandBuilder.delBackChar;
				return;
			case XK_Left:
				commandBuilder.moveLeft((ev.state & ControlMask) != 0);
				return;
			case XK_Right:
				commandBuilder.moveRight((ev.state & ControlMask) != 0);
				return;
			case XK_Tab:
			case XK_Down:
				commandBuilder.select(commandBuilder.selected+1);
				return;
			case XK_ISO_Left_Tab:
			case XK_Up:
				if(!options.lines && commandBuilder.selected == -1){
					showOutput;
				}else
					commandBuilder.select(commandBuilder.selected-1);
				return;
			case XK_Return:
			case XK_KP_Enter:
				commandBuilder.run(!(ev.state & ControlMask));
				if(ev.state & ShiftMask && !options.lines){
					showOutput;
				}
				if(!(ev.state & ControlMask) && !(ev.state & ShiftMask))
					close();
				return;
			default:
				break;
		}
		if(dc.textWidth(buf[0..length].to!string) > 0){
			string s = buf[0..length].to!string;
			commandBuilder.insert(s);
		}
		draw;
	}

	override void onPaste(string text){
		commandBuilder.insert(text);
	}

	void grabKeyboard(){
		foreach(i; 0..100){
			if(XGrabKeyboard(display, DefaultRootWindow(display), true, GrabModeAsync, GrabModeAsync, CurrentTime) == GrabSuccess)
				return;
			Thread.sleep(dur!"msecs"(10));
		}
		close();
		assert(0, "cannot grab keyboard");
	}

}

