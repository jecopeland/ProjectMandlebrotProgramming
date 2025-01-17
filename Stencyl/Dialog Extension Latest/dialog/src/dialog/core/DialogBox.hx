package dialog.core;

#if stencyl

import com.stencyl.graphics.fonts.BitmapFont;
import com.stencyl.graphics.G;
import com.stencyl.models.Font;
import com.stencyl.Engine;

import nme.display.BitmapData;
import nme.geom.Point;
import nme.geom.Rectangle;

#elseif unity

import unityengine.*;
import dialog.unity.compat.Engine;
import dialog.unity.compat.G2;
import dialog.unity.compat.Typedefs;

using dialog.unity.extension.FontUtil;
using dialog.unity.extension.RectUtil;
using dialog.unity.extension.NativeArrayUtil;

#end

import dialog.ext.*;
import dialog.ds.Typedefs;

using dialog.util.BitmapDataUtil;

class DialogBox #if unity extends MonoBehaviour #end
{
	public var dialogSource:String;
	public var style:Style; //Use style to retrieve [default prefs]
	public var dgstyle:DialogStyle; //Use dgstyle to retrieve [command functions]
	public var callbacks:Map<Int, Array<Void->Void>>; //callbackConst, id -> Function
	public var graphicsCallbacks:Map<String, Void->Void>; //layerName -> Function
	public var layers:Array<String>;
	public var cmds:Map<String, Dynamic>; //cmdName, <Function>

	#if unity
	public var callbackObject:Dynamic;
	public var callbackMessage = "";
	public var animations:Array<AnimatedImage>;
	#end

	public var lines:Array<DialogLine>;
	public var curLine:DialogLine;
	public var drawHandler:DrawHandler;
	private var updateCurLineBeforeType:Bool;

	public var dgBase:DialogBase;

	@:isVar public var msgX (get, set):Int;
	@:isVar public var msgY (get, set):Int;
	@:isVar public var msgW (get, set):Int;
	@:isVar public var msgH (get, set):Int;
	@:isVar public var msgFont (get, set):DialogFont;
	@:isVar public var msgColor (get, set):Int;
	public var msgTypeSpeed:Float;
	public var lineSpacing:Int;

	public var drawX:Int;
	private var _font:DialogFontInfo;

	public var typeDelay:Int; //for temporary delays. increment this number, it is reset to 0 every step.
	@:isVar public var paused (get, set):Bool;
	@:isVar public var visible (get, set):Bool;

	public var msg:Array<Dynamic>; //id, <String||Object>
	public var typeIndex:Int;
	public var stepTimer:Int;

	#if stencyl
	public function new(text:String, style:Style)
	#elseif unity
	public function setup(text:String, style:Style)
	#end
	{
		#if stencyl

		if(style == null)
			style = Dialog.defaultStyle;

		#elseif unity

		animations = new Array<AnimatedImage>();
		//TODO

		#end

		dialogSource = text;

		this.style = style;
		dgstyle = DialogStyle.fromStyle(style);
		dgstyle.tieExtensionsToDialogBox(this);
		dgBase = cast(getExt("Dialog Base"), DialogBase);

		lines = new Array<DialogLine>();
		curLine = null;
		updateCurLineBeforeType = false;

		restoreDefaults();

		typeDelay = 0;
		paused = true;
		visible = false;

		callbacks = dgstyle.callbacks;
		graphicsCallbacks = dgstyle.graphicsCallbacks;
		cmds = dgstyle.cmds;

		layers = [];
		for(layer in style.drawOrder)
			layers.push("" + layer);

		drawHandler = null;
	}

	public function set_msgX(value:Int):Int
	{
		if(msgX != value)
		{
			for(line in lines)
			{
				line.moveBy(value - msgX, 0);
			}
		}
		return msgX = value;
	}

	public function get_msgX():Int
	{
		return msgX;
	}

	public function set_msgY(value:Int):Int
	{
		if(msgY != value)
		{
			for(line in lines)
			{
				line.moveBy(0, value - msgY);
			}
		}
		return msgY = value;
	}

	public function get_msgY():Int
	{
		return msgY;
	}

	public function set_msgW(value:Int):Int
	{
		msgW = value;
		if(msgW > 0 && msgH > 0)
		{
			for(line in lines)
			{
				line.setWidth(value);
			}
		}
		return msgW;
	}

	public function get_msgW():Int
	{
		return msgW;
	}

	public function set_msgH(value:Int):Int
	{
		msgH = value;
		if(msgW > 0 && msgH > 0)
		{
			checkOverflow();
		}
		return msgH;
	}

	public function get_msgH():Int
	{
		return msgH;
	}

	public function set_msgFont(value:DialogFont):DialogFont
	{
		msgFont = value;

		updateInternalFont();

		updateCurLineBeforeType = true;
		return msgFont;
	}

	public function get_msgFont():DialogFont
	{
		return msgFont;
	}

	public function set_msgColor(value:Int):Int
	{
		if(msgFont != null)
			msgFont.tempColor = value;

		return msgColor = value;
	}

	public function get_msgColor():Int
	{
		return msgColor;
	}

	private function updateInternalFont():Void
	{
		if(msgFont != null)
			msgFont.tempColor = -1;

		if(msgFont == null)
			msgFont = DialogFont.get(null);

		_font = msgFont.info;

		msgFont.tempColor = msgColor;
	}

	public function set_paused(value:Bool):Bool
	{
		if(msg != null && paused != value)
		{
			if(value) //trying to pause
				runCallbacks(Dialog.WHEN_TYPING_ENDS);
			else //trying to unpause
				runCallbacks(Dialog.WHEN_TYPING_BEGINS);
		}

		return paused = value;
	}

	public function get_paused():Bool
	{
		return paused;
	}

	public function set_visible(value:Bool):Bool
	{
		if(visible != value)
		{
			if(value) //trying to show
				runCallbacks(Dialog.WHEN_MESSAGE_SHOWN);
			else //trying to hide
				runCallbacks(Dialog.WHEN_MESSAGE_HIDDEN);
		}

		return visible = value;
	}

	public function get_visible():Bool
	{
		return visible;
	}

	public function beginDialog():Void
	{
		runCallbacks(Dialog.WHEN_CREATED);

		resetMessageVars();

		msg = Dialog.parseMessage(dialogSource);

		visible = true;
		paused = false;

		runCallbacks(Dialog.WHEN_MESSAGE_BEGINS);
		runCallbacks(Dialog.WHEN_MESSAGE_SHOWN);
	}

	public function continueNewDialog():Void
	{
		resetMessageVars();

		msg = Dialog.parseMessage(dialogSource);

		visible = true;
		paused = false;
	}

	public function insertMessage(insert:String):Void
	{
		var toAdd:Array<String> = insert.split("");
		for(i in 0...toAdd.length)
		{
			msg.insert(typeIndex + 1 + i, toAdd[i]);
		}
		if(wordwrapCheck())
		{
			startNextLine();
		}
	}

	public function clearMessage():Void
	{
		cleanLines();
		runCallbacks(Dialog.WHEN_MESSAGE_CLEARED);
	}

	public function closeMessage():Void
	{
		clearMessage();
		resetMessageVars();
		runCallbacks(Dialog.WHEN_TYPING_ENDS);
		runCallbacks(Dialog.WHEN_MESSAGE_HIDDEN);
	}

	public function endMessage():Void
	{
		closeMessage();
		runCallbacks(Dialog.WHEN_MESSAGE_ENDS);

		#if stencyl

		Dialog.get().removeDialogBox(this);

		#elseif unity

		if(callbackObject != null && callbackMessage != "")
			Reflect.callMethod(callbackObject, Reflect.field(callbackObject, callbackMessage), []);

		Object.Destroy(this);

		#end
	}

	public var defaultBounds:Rectangle;

	public function restoreDefaults():Void
	{
		#if stencyl
		if(style.fitMsgToWindow)
		{
			var w:DialogWindow = dgBase.getWindow();
			if(w != null)
			{
				msgX = Std.int(w.position.x + w.template.insets.x);
				msgY = Std.int(w.position.y + w.template.insets.y);
				msgW = Std.int(w.size.x - w.template.insets.x - w.template.insets.width);
				msgH = Std.int(w.size.y - w.template.insets.y - w.template.insets.height);
			}
		}
		else
		{
		#end
			msgX = Std.int(dgBase.getStyle().msgBounds.x);
			msgY = Std.int(dgBase.getStyle().msgBounds.y);
			msgW = Std.int(dgBase.getStyle().msgBounds.width);
			msgH = Std.int(dgBase.getStyle().msgBounds.height);
		#if stencyl
		}
		#end
		defaultBounds = new Rectangle(msgX, msgY, msgW, msgH);
		msgColor = -1;
		msgFont = DialogFont.get(dgBase.getStyle().msgFont);
		msgTypeSpeed = dgBase.getStyle().msgTypeSpeed;
		lineSpacing = dgBase.getStyle().lineSpacing;

		runCallbacks(Dialog.RESTORE_DEFAULTS);
	}

	private function resetMessageVars():Void
	{
		//clean variables
		restoreDefaults();
		cleanLines();
		paused = false;
		visible = false;
		msg = null;
		typeIndex = -1;
	}

	private function cleanLines():Void
	{
		for(line in lines)
		{
			for(handle in line.drawHandledChars)
			{
				handle.removeImg();
			}
		}
		lines.splice(0, lines.length);
		curLine = null;
		startNextLine();
	}

	private var lastChar:String = "";
	private var char:String = "";

	private function messageStep():Void
	{
		typeDelay = 0;
		if(Std.is(msg[typeIndex], String))
		{
			char = Std.string(msg[typeIndex]);

			if(char == "\n" || char == "\r" || char == "\t")
			{
				//do nothing for special whitespace characters.
			}
			else
			{
				if((lastChar == " " && wordwrapCheck()) || (char != " " && charOobCheck()))
					startNextLine();
				if(char != " " && updateCurLineBeforeType)
				{
					updateCurLineBeforeType = false;
					curLine.setFont(msgFont);
					checkOverflow();
				}

				//Unity fix - maybe applies to Stencyl too.
				if(drawX + _font.getOffset(char).x < 0)
					drawX -= cast _font.getOffset(char).x;

				if(drawHandler != null)
				{
					var charID:Int = drawHandler.addImg(
						msgFont.getScaledChar(char),
						G2.s(msgX + drawX) + Std.int(_font.getScaledOffset(char).x),
						G2.s(curLine.pos.y) + Std.int(_font.getScaledOffset(char).y) + (G2.s(curLine.aboveBase) - _font.scaledAboveBase),
						false);
					curLine.drawHandledChars.push(new DrawHandledImage(drawHandler, charID));
				}
				else
					curLine.img.drawChar(char, msgFont, G2.s(drawX), G2.s(curLine.aboveBase) - _font.scaledAboveBase);

				drawX += _font.getAdvance(char) + dgBase.getStyle().charSpacing;

				runCallbacks(Dialog.WHEN_CHAR_TYPED);
			}
			typeDelay = Std.int(msgTypeSpeed * 1000);
			lastChar = char;
		}
		else
		{
			executeTag(cast(msg[typeIndex], Tag));
		}
	}

	private function wordwrapCheck():Bool
	{
		var tempDrawX:Int = drawX;
		var tempMsgDisplay:String = "";
		var i:Int = typeIndex;
		if(msg[i] == " ")
		{
			tempDrawX += _font.getAdvance(Std.string(msg[i])) + dgBase.getStyle().charSpacing;
			++i;
		}
		while(msg[i] != " ")
		{
			if(Std.is(msg[i], String))
			{
				tempMsgDisplay += Std.string(msg[i]);
				tempDrawX += _font.getAdvance(Std.string(msg[i])) + dgBase.getStyle().charSpacing;
			}
			++i;
			if(i > msg.length - 1)
			{
				break;
			}
		}
		return tempDrawX > msgW;
	}

	private function charOobCheck():Bool
	{
		return drawX + _font.getAdvance(Std.string(msg[typeIndex])) > msgW;
	}

	public function startNextLine():Void
	{
		drawX = 0;
		var startY = msgY;

		if(curLine != null)
			startY = Std.int(curLine.pos.y + curLine.pos.height) + lineSpacing;

		curLine = new DialogLine(msgFont, new Rectangle(msgX, startY, msgW, 0));
		lines.push(curLine);

		checkOverflow();
	}

	private function checkOverflow():Void
	{
		if(curLine == null)
			return;

		while(curLine.pos.y + curLine.pos.height > msgY + msgH)
		{
			var removedLine:DialogLine = lines.shift();
			if(removedLine == null)
				break;

			for(handle in removedLine.drawHandledChars)
			{
				handle.removeImg();
			}

			for(line in lines)
			{
				line.moveBy(0, -(Std.int(removedLine.pos.height) + lineSpacing));
			}
		}
	}

	private function executeTag(tag:Tag):Dynamic
	{
		for(i in 0...tag.argArray.length)
		{
			if(Std.is(tag.argArray[i], Array))
			{
				tag.argArray[i] = executeTagsInList(tag.argArray[i]);
			}
			else if(Std.is(tag.argArray[i], Tag))
				tag.argArray[i] = executeTag(tag.argArray[i]);
		}

		if(!cmds.exists(tag.name))
		{
			trace("Could not find tag: " + tag.name);
			return null;
		}
		else
		{
			try
			{
				//TODO: is this correct? The first argument isn't the proper object to be calling on.
				return Reflect.callMethod(cmds.get(tag.name), cmds.get(tag.name), tag.argArray);
			}
			catch( error:Dynamic )
			{
				trace('Error occurred while executing command: $tag');
				trace(error);
				return null;
			}
		}
	}

	private function executeTagsInList(list:Array<Dynamic>):Array<Dynamic>
	{
		for(i in 0...list.length)
		{
			if(Std.is(list[i], Array))
			{
				list[i] = executeTagsInList(list[i]);
			}
			else if(Std.is(list[i], Tag))
				list[i] = executeTag(list[i]);
		}

		return list;
	}

	#if unity
	public function Update():Void
	{
		for(curAnimation in animations)
		{
			curAnimation.update();
		}

		update();
	}

	public function OnPostRender():Void
	{
		draw();
	}

	public function addAnimation(anim:AnimatedImage):Void
	{
		animations.push(anim);
	}

	public function removeAnimation(anim:AnimatedImage):Void
	{
		for(i in 0...animations.length)
		{
			if(animations[i] == anim)
			{
				animations.splice(i, 1);
				break;
			}
		}
	}
	#end

	public function update():Void
	{
		if(msg == null)
			return;

		if(!paused && typeIndex < msg.length - 1)
		{
			if(stepTimer > 0)
			{
				stepTimer -= Engine.STEP_SIZE;
			}
			while(stepTimer <= 0)
			{
				++typeIndex;
				messageStep();
				stepTimer += Std.int(msgTypeSpeed) + typeDelay;

				if(paused || msg == null || typeIndex >= msg.length - 1) break;
			}
		}

		runCallbacks(Dialog.ALWAYS);
	}

	public function draw():Void
	{
		if(visible)
		{
			#if stencyl
			Engine.engine.g.alpha = 1;
			#elseif unity
			GL.PushMatrix();
			GL.LoadPixelMatrix(0, Screen.width, Screen.height, 0);
			#end

			for(layerKey in layers)
			{
				if(graphicsCallbacks.exists(layerKey))
				{
					graphicsCallbacks.get(layerKey)();
				}
				else
				{
					trace("Undefined draw key: " + layerKey);
				}
			}

			#if unity
			GL.PopMatrix();
			#end
		}
	}

	public function runCallbacks(callbackConst:Int):Void
	{
		if(callbacks == null) return;

		var a:Array<Void->Void> = callbacks.get(callbackConst);
		if(a != null)
		{
			for(i in 0...a.length)
			{
				a[i]();
			}
		}
	}

	public function goToDialog(toCall:String)
	{
		dialogSource = Dialog.dialogCache.get(toCall);

		continueNewDialog();
	}

	public function getExt(extName:String):DialogExtension
	{
		return dgstyle.extensionMap.get(extName);
	}
}

private class DialogLine
{
	public var pos:Rectangle;

	public var aboveBase:Int;
	public var belowBase:Int;

	public var drawHandledChars:Array<DrawHandledImage>;
	public var img:BitmapData;

	public function new(font:DialogFont, pos:Rectangle)
	{
		this.pos = pos.clone();

		aboveBase = font.info.aboveBase;
		belowBase = font.info.belowBase;

		this.pos.height = aboveBase + belowBase + 1;

		drawHandledChars = new Array<DrawHandledImage>();

		img = BitmapDataUtil.newTransparentImg(G2.s(this.pos.width), G2.s(this.pos.height));
	}

	public function setFont(font:DialogFont):Void
	{
		var increase:Int = 0;

		if(font.info.belowBase > belowBase)
		{
			increase = (font.info.belowBase - belowBase);

			belowBase = font.info.belowBase;
		}

		if(font.info.aboveBase > aboveBase)
		{
			var shift:Int = (font.info.aboveBase - aboveBase);
			increase += shift;

			aboveBase = font.info.aboveBase;

			var tempImg:BitmapData = BitmapDataUtil.newTransparentImg(img.width, img.height + G2.s(increase));
			tempImg.drawImage(img, 0, shift);
			img = tempImg;
			pos.width = img.width;
			pos.height = img.height;
			for(handle in drawHandledChars)
			{
				handle.moveImgBy(0, G2.s(shift));
			}
		}
	}

	public function setWidth(width:Int):Void
	{
		if(G2.s(width) == img.width)
			return;

		var tempImg:BitmapData = BitmapDataUtil.newTransparentImg(G2.s(width), img.height);
		tempImg.copyPixels(img, new Rectangle(0, 0, Math.min(img.width, tempImg.width), img.height), new Point(0, 0));

		img = tempImg;
		pos.width = width;
		//pos.height = img.height; Is this needed?
	}

	public function moveBy(x:Int, y:Int):Void
	{
		pos.x = pos.x + x;
		pos.y = pos.y + y;

		for(handle in drawHandledChars)
		{
			handle.moveImgBy(G2.s(x), G2.s(y));
		}
	}
}
