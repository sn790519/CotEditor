/*
 ==============================================================================
 CETextView
 
 CotEditor
 http://coteditor.com
 
 Created on 2005-03-30 by nakamuxu
 encoding="UTF-8"
 
 ------------
 This class is based on JSDTextView (written by James S. Derry – http://www.balthisar.com)
 JSDTextView is released as public domain.
 arranged by nakamuxu, Dec 2004.
 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
 © 2014-2015 1024jp
 
 This program is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation; either version 2 of the License, or (at your option) any later
 version.
 
 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License along with
 this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 Place - Suite 330, Boston, MA  02111-1307, USA.
 
 ==============================================================================
 */

#import "CETextView.h"
#import "CELineNumberView.h"
#import "CEColorCodePanelController.h"
#import "CEGlyphPopoverController.h"
#import "CEKeyBindingManager.h"
#import "CEScriptManager.h"
#import "NSString+JapaneseTransform.h"
#import "constants.h"


// constant
const NSInteger kNoMenuItem = -1;


@interface CETextView ()

@property (nonatomic) NSRect insertionRect;
@property (nonatomic) NSPoint textContainerOriginPoint;
@property (nonatomic) NSMutableParagraphStyle *paragraphStyle;
@property (nonatomic) NSTimer *completionTimer;
@property (nonatomic) NSString *particalCompletionWord;  // ユーザが実際に入力した補完の元になる文字列

@property (nonatomic) NSColor *highlightLineColor;  // カレント行ハイライト色


// readonly
@property (readwrite, nonatomic, getter=isSelfDrop) BOOL selfDrop;  // 自己内ドラッグ&ドロップなのか
@property (readwrite, nonatomic, getter=isReadingFromPboard) BOOL readingFromPboard;  // ペーストまたはドロップ実行中なのか

@end




#pragma mark -

@implementation CETextView

#pragma mark Superclass Methods

// ------------------------------------------------------
/// initialize
- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(NSTextContainer *)aTextContainer
// ------------------------------------------------------
{
    self = [super initWithFrame:frameRect textContainer:aTextContainer];
    if (self) {
        // This method is partly based on Smultron's SMLTextView by Peter Borg. (2006-09-09)
        // Smultron 2 was distributed on <http://smultron.sourceforge.net> under the terms of the BSD license.
        // Copyright (c) 2004-2006 Peter Borg
        
        // set the width of every tab by first checking the size of the tab in spaces in the current font and then remove all tabs that sets automatically and then set the default tab stop distance
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        _tabWidth = [defaults integerForKey:CEDefaultTabWidthKey];
        
        CGFloat fontSize = (CGFloat)[defaults doubleForKey:CEDefaultFontSizeKey];
        NSFont *font = [NSFont fontWithName:[defaults stringForKey:CEDefaultFontNameKey] size:fontSize];
        if (!font) {
            font = [NSFont systemFontOfSize:fontSize];
        }

        NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        for (NSTextTab *textTabToBeRemoved in [paragraphStyle tabStops]) {
            [paragraphStyle removeTabStop:textTabToBeRemoved];
        }
        [paragraphStyle setDefaultTabInterval:[self tabIntervalFromFont:font]];
        _paragraphStyle = paragraphStyle;
        // （NSParagraphStyle の lineSpacing を設定すればテキスト描画時の行間は制御できるが、
        // 「文書の1文字目に1バイト文字（または2バイト文字）を入力してある状態で先頭に2バイト文字（または1バイト文字）を
        // 挿入すると行間がズレる」問題が生じるため、CELayoutManager および CEATSTypesetter で制御している）

        // setup theme
        [self setTheme:[CETheme themeWithName:[defaults stringForKey:CEDefaultThemeKey]]];
        
        // set values
        _autoTabExpandEnabled = [defaults boolForKey:CEDefaultAutoExpandTabKey];
        [self setSmartInsertDeleteEnabled:[defaults boolForKey:CEDefaultSmartInsertAndDeleteKey]];
        [self setContinuousSpellCheckingEnabled:[defaults boolForKey:CEDefaultCheckSpellingAsTypeKey]];
        if ([self respondsToSelector:@selector(setAutomaticQuoteSubstitutionEnabled:)]) {  // only on OS X 10.9 and later
            [self setAutomaticQuoteSubstitutionEnabled:[defaults boolForKey:CEDefaultEnableSmartQuotesKey]];
            [self setAutomaticDashSubstitutionEnabled:[defaults boolForKey:CEDefaultEnableSmartQuotesKey]];
        }
        [self setFont:font];
        [self setMinSize:frameRect.size];
        [self setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
        [self setAllowsDocumentBackgroundColorChange:NO];
        [self setAllowsUndo:YES];
        [self setRichText:NO];
        [self setImportsGraphics:NO];
        [self setUsesFindPanel:YES];
        [self setHorizontallyResizable:YES];
        [self setVerticallyResizable:YES];
        [self setAcceptsGlyphInfo:YES];
        [self setTextContainerInset:NSMakeSize((CGFloat)[defaults doubleForKey:CEDefaultTextContainerInsetWidthKey],
                                               (CGFloat)([defaults doubleForKey:CEDefaultTextContainerInsetHeightTopKey] +
                                                         [defaults doubleForKey:CEDefaultTextContainerInsetHeightBottomKey]) / 2)];
        [self setLineSpacing:(CGFloat)[defaults doubleForKey:CEDefaultLineSpacingKey]];
        _insertionRect = NSZeroRect;
        _textContainerOriginPoint = NSMakePoint((CGFloat)[defaults doubleForKey:CEDefaultTextContainerInsetWidthKey],
                                                (CGFloat)[defaults doubleForKey:CEDefaultTextContainerInsetHeightTopKey]);
        _needsUpdateOutlineMenuItemSelection = YES;
        
        [self applyTypingAttributes];
        
        // observe change of defaults
        for (NSString *key in [CETextView observedDefaultKeys]) {
            [[NSUserDefaults standardUserDefaults] addObserver:self
                                                    forKeyPath:key
                                                       options:NSKeyValueObservingOptionNew
                                                       context:NULL];
        }
    }

    return self;
}


// ------------------------------------------------------
/// clean up
- (void)dealloc
// ------------------------------------------------------
{
    for (NSString *key in [CETextView observedDefaultKeys]) {
        [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:key];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopCompletionTimer];
}


// ------------------------------------------------------
/// first responder になれるかを返す
- (BOOL)becomeFirstResponder
// ------------------------------------------------------
{
    [[(CEWindowController *)[[self window] windowController] editor] setTextView:self];
    
    return [super becomeFirstResponder];
}


// ------------------------------------------------------
/// 自身がウインドウに組み込まれた
-(void)viewDidMoveToWindow
// ------------------------------------------------------
{
    [super viewDidMoveToWindow];
    
    // テーマ背景色を反映させる
    [[self window] setBackgroundColor:[[self theme] backgroundColor]];
    
    // レイヤーバックドビューにする
    [[self enclosingScrollView] setWantsLayer:YES];
    [[[self enclosingScrollView] contentView] setCopiesOnScroll:YES];
    [self setLayerContentsRedrawPolicy:NSViewLayerContentsRedrawOnSetNeedsDisplay];
    
    // ウインドウの透明フラグを監視する
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didWindowOpacityChange:)
                                                 name:CEWindowOpacityDidChangeNotification
                                               object:[self window]];
}


// ------------------------------------------------------
/// キー押下を取得
- (void)keyDown:(NSEvent *)theEvent
// ------------------------------------------------------
{
    NSString *charIgnoringMod = [theEvent charactersIgnoringModifiers];
    // IM で日本語入力変換中でないときのみ追加テキストキーバインディングを実行
    if (![self hasMarkedText] && charIgnoringMod) {
        NSString *selectorStr = [[CEKeyBindingManager sharedManager] selectorStringWithKeyEquivalent:charIgnoringMod
                                                                                       modifierFrags:[theEvent modifierFlags]];
        NSInteger length = [selectorStr length];
        if (selectorStr && (length > 0)) {
            if (([selectorStr hasPrefix:@"insertCustomText"]) && (length == 20)) {
                NSInteger theNum = [[selectorStr substringFromIndex:17] integerValue];
                [self insertCustomTextWithPatternNum:theNum];
            } else {
                [self doCommandBySelector:NSSelectorFromString(selectorStr)];
            }
            return;
        }
    }
    
    [super keyDown:theEvent];
}


// ------------------------------------------------------
/// on inputting text (NSTextInputClient Protocol)
- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange
// ------------------------------------------------------
{
    // swap '¥' with '\' if needed
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultSwapYenAndBackSlashKey] && ([aString length] == 1)) {
        NSEvent *event = [NSApp currentEvent];
        NSUInteger flags = [NSEvent modifierFlags];
        
        if (([event type] == NSKeyDown) && (flags == 0)) {  // ignore input by "Insert Yen/Backslash" menu action
            NSString *yen = [NSString stringWithCharacters:&kYenMark length:1];
            
            if ([aString isEqual:@"\\"]) {  // Don't use isEqualToString: since aString can be a NSAttributedString.
                [super insertText:yen replacementRange:replacementRange];
                return;
            } else if ([aString isEqual:yen]) {
                [super insertText:@"\\" replacementRange:replacementRange];
                return;
            }
        }
    }
    
    // smart outdent with '}' charcter
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultAutoIndentKey] &&
        [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultEnableSmartIndentKey] &&
        (replacementRange.length == 0) && [aString isEqual:@"}"])
    {
        NSString *wholeString = [self string];
        NSUInteger insretionLocation = NSMaxRange([self selectedRange]);
        NSRange lineRange = [wholeString lineRangeForRange:NSMakeRange(insretionLocation, 0)];
        NSString *lineStr = [wholeString substringWithRange:lineRange];
        
        // decrease indent level if the line is consists of only whitespaces
        if ([lineStr rangeOfString:@"^[ \\t　]+\\n?$"
                           options:NSRegularExpressionSearch
                             range:NSMakeRange(0, [lineStr length])].location != NSNotFound)
        {
            // find correspondent opening-brace
            NSInteger precedingLocation = insretionLocation - 1;
            NSUInteger skipMatchingBrace = 0;
            
            while (precedingLocation--) {
                unichar characterToCheck = [wholeString characterAtIndex:precedingLocation];
                if (characterToCheck == '{') {
                    if (skipMatchingBrace) {
                        skipMatchingBrace--;
                    } else {
                        break;  // found
                    }
                } else if (characterToCheck == '}') {
                    skipMatchingBrace++;
                }
            }
            
            // outdent
            if (precedingLocation >= 0) {
                NSRange precedingLineRange = [wholeString lineRangeForRange:NSMakeRange(precedingLocation, 0)];
                NSString *precedingLineStr = [wholeString substringWithRange:precedingLineRange];
                NSUInteger desiredLevel = [self indentLevelOfString:precedingLineStr];
                NSUInteger currentLevel = [self indentLevelOfString:lineStr];
                NSUInteger levelToReduce = currentLevel - desiredLevel;
                
                while (levelToReduce--) {
                    [self deleteBackward:self];
                }
            }
        }
    }
    
    [super insertText:aString replacementRange:replacementRange];
    
    // auto completion
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultAutoCompleteKey]) {
        [self completeAfterDelay:[[NSUserDefaults standardUserDefaults] doubleForKey:CEDefaultAutoCompletionDelayKey]];
    }
}


// ------------------------------------------------------
/// タブ入力、タブを展開
- (void)insertTab:(id)sender
// ------------------------------------------------------
{
    if ([self isAutoTabExpandEnabled]) {
        NSInteger tabWidth = [self tabWidth];
        NSInteger column = [self columnOfLocation:[self selectedRange].location expandsTab:YES];
        NSInteger length = tabWidth - ((column + tabWidth) % tabWidth);
        NSMutableString *spaces = [NSMutableString string];

        while (length--) {
            [spaces appendString:@" "];
        }
        [super insertText:spaces];
        
    } else {
        [super insertTab:sender];
    }
}


// ------------------------------------------------------
/// 改行コード入力、オートインデント実行
- (void)insertNewline:(id)sender
// ------------------------------------------------------
{
    NSString *indent = @"";
    BOOL shouldIncreaseIndentLevel = NO;
    BOOL shouldExpandBlock = NO;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultAutoIndentKey]) {
        NSRange selectedRange = [self selectedRange];
        NSRange lineRange = [[self string] lineRangeForRange:selectedRange];
        NSString *lineStr = [[self string] substringWithRange:NSMakeRange(lineRange.location,
                                                                          NSMaxRange(selectedRange) - lineRange.location)];
        NSRange indentRange = [lineStr rangeOfString:@"^[ \\t　]+" options:NSRegularExpressionSearch];
        
        // インデントを選択状態で改行入力した時は置換とみなしてオートインデントしない 2008-12-13
        if (NSMaxRange(selectedRange) >= (selectedRange.location + NSMaxRange(indentRange))) {
            [super insertNewline:sender];
            return;
        }
            
        if (indentRange.location != NSNotFound) {
            indent = [lineStr substringWithRange:indentRange];
        }
        
        // smart indent
        if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultEnableSmartIndentKey]) {
            unichar lastChar = NULL;
            unichar nextChar = NULL;
            if (selectedRange.location > 0) {
                lastChar = [[self string] characterAtIndex:selectedRange.location - 1];
            }
            if (NSMaxRange(selectedRange) < [[self string] length]) {
                nextChar = [[self string] characterAtIndex:NSMaxRange(selectedRange)];
            }
            // `{}` の中で改行した場合はインデントを展開する
            shouldExpandBlock = ((lastChar == '{') && (nextChar == '}'));
            // 改行直前の文字が `:` か `{` の場合はインデントレベルを1つ上げる
            shouldIncreaseIndentLevel = ((lastChar == ':') || (lastChar == '{'));
        }
    }
    
    [super insertNewline:sender];
    
    if ([indent length] > 0) {
        [super insertText:indent];
    }
    
    if (shouldExpandBlock) {
        [self insertTab:sender];
        NSRange selection = [self selectedRange];
        [super insertNewline:sender];
        [super insertText:indent];
        [self setSelectedRange:selection];
        
    } else if (shouldIncreaseIndentLevel) {
        [self insertTab:sender];
    }
}


// ------------------------------------------------------
/// デリート、タブを展開しているときのスペースを調整削除
- (void)deleteBackward:(id)sender
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    if (selectedRange.length == 0 && [self isAutoTabExpandEnabled]) {
        NSUInteger tabWidth = [self tabWidth];
        NSInteger column = [self columnOfLocation:selectedRange.location expandsTab:YES];
        NSInteger length = tabWidth - ((column + tabWidth) % tabWidth);
        NSInteger targetWidth = (length == 0) ? tabWidth : length;
        
        if (selectedRange.location >= targetWidth) {
            NSRange targetRange = NSMakeRange(selectedRange.location - targetWidth, targetWidth);
            NSString *target = [[self string] substringWithRange:targetRange];
            BOOL shouldDelete = NO;
            for (NSUInteger i = 0; i < targetWidth; i++) {
                shouldDelete = ([target characterAtIndex:i] == ' ');
                if (!shouldDelete) {
                    break;
                }
            }
            if (shouldDelete) {
                [self setSelectedRange:targetRange];
            }
        }
    }
    [super deleteBackward:sender];
}


// ------------------------------------------------------
/// コンテキストメニューを返す
- (NSMenu *)menuForEvent:(NSEvent *)theEvent
// ------------------------------------------------------
{
    NSMenu *menu = [super menuForEvent:theEvent];

    // remove unwanted "Font" menu and its submenus
    [menu removeItem:[menu itemWithTitle:NSLocalizedString(@"Font", nil)]];
    
    // add "Inspect Character" menu item if single character is selected
    if ([[[self string] substringWithRange:[self selectedRange]] numberOfComposedCharacters] == 1) {
        [menu insertItemWithTitle:NSLocalizedString(@"Inspect Character", nil)
                              action:@selector(showSelectionInfo:)
                       keyEquivalent:@""
                             atIndex:1];
    }
    
    // add "Select All" menu item
    NSInteger pasteIndex = [menu indexOfItemWithTarget:nil andAction:@selector(paste:)];
    if (pasteIndex != kNoMenuItem) {
        [menu insertItemWithTitle:NSLocalizedString(@"Select All", nil)
                           action:@selector(selectAll:) keyEquivalent:@""
                          atIndex:(pasteIndex + 1)];
    }
    
    // append a separator
    [menu addItem:[NSMenuItem separatorItem]];
    
    // append Utility menu
    NSMenuItem *utilityMenuItem = [[NSApp mainMenu] itemAtIndex:CEUtilityMenuIndex];
    if (utilityMenuItem) {
        [menu addItem:[utilityMenuItem copy]];
    }
    
    // append Script menu
    NSMenu *scriptMenu = [[CEScriptManager sharedManager] contexualMenu];
    if (scriptMenu) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultInlineContextualScriptMenuKey]) {
            [menu addItem:[NSMenuItem separatorItem]];
            [[[menu itemArray] lastObject] setTag:CEScriptMenuItemTag];
            
            for (NSMenuItem *item in [scriptMenu itemArray]) {
                NSMenuItem *addItem = [item copy];
                [addItem setTag:CEScriptMenuItemTag];
                [menu addItem:addItem];
            }
            [menu addItem:[NSMenuItem separatorItem]];
            
        } else {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            [item setImage:[NSImage imageNamed:@"ScriptTemplate"]];
            [[item image] setTemplate:NO];  // draw in black
            [item setTag:CEScriptMenuItemTag];
            [item setSubmenu:scriptMenu];
            [menu addItem:item];
        }
    }
    
    return menu;
}


// ------------------------------------------------------
/// コピー実行。改行コードを書類に設定されたものに置換する。
- (void)copy:(id)sender
// ------------------------------------------------------
{
    // （このメソッドは cut: からも呼び出される）
    [super copy:sender];
    [self replaceLineEndingToDocCharInPboard:[NSPasteboard generalPasteboard]];
}


// ------------------------------------------------------
/// フォント変更
- (void)changeFont:(id)sender
// ------------------------------------------------------
{
    // (引数"sender"はNSFontManegerのインスタンス)
    NSFont *newFont = [sender convertFont:[self font]];

    [self setFont:newFont];
    [self setNeedsDisplay:YES]; // 本来なくても再描画されるが、最下行以下のページガイドの描画が残るための措置 (2009-02-14)
    [self updateLineNumberAndAdjustScroll];
}


// ------------------------------------------------------
/// フォントを設定
- (void)setFont:(NSFont *)font
// ------------------------------------------------------
{
// 複合フォントで行間が等間隔でなくなる問題を回避するため、CELayoutManager にもフォントを持たせておく。
// （CELayoutManager で [[self firstTextView] font] を使うと、「1バイトフォントを指定して日本語が入力されている」場合に
// 日本語フォント名を返してくることがあるため、CELayoutManager からは [textView font] を使わない）
    
    [(CELayoutManager *)[self layoutManager] setTextFont:font];
    [super setFont:font];
    
    [[self paragraphStyle] setDefaultTabInterval:[self tabIntervalFromFont:font]];
    
    [self applyTypingAttributes];
}


// ------------------------------------------------------
/// タブ幅を変更
- (void)setTabWidth:(NSUInteger)tabWidth
// ------------------------------------------------------
{
    _tabWidth = tabWidth;
    [self setFont:[self font]];  // force re-layout with new width
}


// ------------------------------------------------------
/// テキストコンテナの原点（左上）座標を返す
- (NSPoint)textContainerOrigin
// ------------------------------------------------------
{
    return [self textContainerOriginPoint];
}


// ------------------------------------------------------
/// ビュー内の背景を描画
- (void)drawViewBackgroundInRect:(NSRect)rect
// ------------------------------------------------------
{
    [super drawViewBackgroundInRect:rect];
    
    // draw current line highlight
    if (!NSIsEmptyRect([self highlightLineRect])) {
        [[self highlightLineColor] set];
        [NSBezierPath fillRect:[self highlightLineRect]];
    }
}


// ------------------------------------------------------
/// ビュー内を描画
- (void)drawRect:(NSRect)dirtyRect
// ------------------------------------------------------
{
    [super drawRect:dirtyRect];
    
    // draw page guide
    if ([self showsPageGuide]) {
        CGFloat column = (CGFloat)[[NSUserDefaults standardUserDefaults] doubleForKey:CEDefaultPageGuideColumnKey];
        
        if ((column < kMinPageGuideColumn) || (column > kMaxPageGuideColumn)) {
            return;
        }
        
        CGFloat length = ([self layoutOrientation] == NSTextLayoutOrientationVertical) ? NSWidth([self frame]) : NSHeight([self frame]);
        CGFloat linePadding = [[self textContainer] lineFragmentPadding];
        CGFloat inset = [self textContainerOrigin].x;
        
        NSFont *font = [self typingAttributes][NSFontAttributeName];
        font = [font screenFont] ? : font;
        column *= [@"M" sizeWithAttributes:@{NSFontAttributeName:font}].width;
        
        CGFloat x = floor(column + inset + linePadding) + 2.5;  // +2px for adjusting
        [[[self textColor] colorWithAlphaComponent:0.2] set];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, 0)
                                  toPoint:NSMakePoint(x, length)];
    }
}


// ------------------------------------------------------
/// 特定の範囲が見えるようにスクロール
- (void)scrollRangeToVisible:(NSRange)range
// ------------------------------------------------------
{
    // 矢印キーが押されているときは1行ずつのスクロールにする
    if ([NSEvent modifierFlags] & NSNumericPadKeyMask) {
        NSRange glyphRange = [[self layoutManager] glyphRangeForCharacterRange:range actualCharacterRange:nil];
        NSRect glyphRect = [[self layoutManager] boundingRectForGlyphRange:glyphRange inTextContainer:[self textContainer]];
        CGFloat buffer = [[self font] pointSize] / 2;
        
        glyphRect = NSInsetRect(glyphRect, -buffer, -buffer);
        glyphRect = NSOffsetRect(glyphRect, [self textContainerOrigin].x, [self textContainerOrigin].y);
        
        [super scrollRectToVisible:glyphRect];  // move minimum distance
        
        return;
    }
    
    [super scrollRangeToVisible:range];
    
    // 完全にスクロールさせる
    // （setTextContainerInset で上下に空白領域を挿入している関係で、ちゃんとスクロールしない場合があることへの対策）
    NSUInteger length = [[self string] length];
    NSRect rect = NSZeroRect;
    
    if (length == range.location) {
        rect = [[self layoutManager] extraLineFragmentRect];
    } else if (length > range.location) {
        NSString *tailStr = [[self string] substringFromIndex:range.location];
        if ([tailStr detectNewLineType] != CENewLineNone) {
            return;
        }
    }
    
    if (NSEqualRects(rect, NSZeroRect)) {
        NSRange targetRange = [[self string] lineRangeForRange:range];
        NSRange glyphRange = [[self layoutManager] glyphRangeForCharacterRange:targetRange actualCharacterRange:nil];
        rect = [[self layoutManager] lineFragmentRectForGlyphAtIndex:(NSMaxRange(glyphRange) - 1)
                                                      effectiveRange:nil];
    }
    if (NSEqualRects(rect, NSZeroRect)) { return; }
    
    NSRect convertedRect = [self convertRect:rect toView:[[self enclosingScrollView] superview]]; //editorView
    if ((convertedRect.origin.y >= 0) &&
        (convertedRect.origin.y < [[NSUserDefaults standardUserDefaults] doubleForKey:CEDefaultTextContainerInsetHeightBottomKey]))
    {
        [self scrollPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    }
}


// ------------------------------------------------------
/// 表示方向を変更
- (void)setLayoutOrientation:(NSTextLayoutOrientation)theOrientation
// ------------------------------------------------------
{
    if (theOrientation != [self layoutOrientation]) {
        BOOL isVertical = (theOrientation == NSTextLayoutOrientationVertical);
        
        // 折り返しを再セット
        if ([[self textContainer] containerSize].width != CGFLOAT_MAX) {
            [[self textContainer] setContainerSize:NSMakeSize(0, CGFLOAT_MAX)];
        }
        
        // 縦書きのときは強制的に行番号ビューを非表示
        BOOL showsLineNum = isVertical ? NO : [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultShowLineNumbersKey];
        [(CELineNumberView *)[self lineNumberView] setShown:showsLineNum];
    }
    
    [super setLayoutOrientation:theOrientation];
}


// ------------------------------------------------------
/// 読み取り可能なPasteboardタイプを返す
- (NSArray *)readablePasteboardTypes
// ------------------------------------------------------
{
    return [[super readablePasteboardTypes] arrayByAddingObject:NSFilenamesPboardType];
}


// ------------------------------------------------------
/// ドラッグする文字列の改行コードを書類に設定されたものに置換する
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray *)items event:(NSEvent *)event source:(id<NSDraggingSource>)source
// ------------------------------------------------------
{
    NSDraggingSession *session = [super beginDraggingSessionWithItems:items event:event source:source];
    
    [self replaceLineEndingToDocCharInPboard:[session draggingPasteboard]];
    
    return session;
}


// ------------------------------------------------------
/// 領域内でオブジェクトがドラッグされている
- (NSDragOperation)dragOperationForDraggingInfo:(id <NSDraggingInfo>)dragInfo type:(NSString *)type
// ------------------------------------------------------
{
    if (![type isEqualToString:NSFilenamesPboardType]) {
        return [super dragOperationForDraggingInfo:dragInfo type:type];
    }
    
    NSArray *fileDropArray = [[NSUserDefaults standardUserDefaults] arrayForKey:CEDefaultFileDropArrayKey];
    NSArray *array = [[dragInfo draggingPasteboard] propertyListForType:NSFilenamesPboardType];
    
    for (NSDictionary *item in fileDropArray) {
        NSArray *extensions = [item[CEFileDropExtensionsKey] componentsSeparatedByString:@", "];
        
        if ([self draggedItemsArray:array containsExtensionInExtensions:extensions]) {
            NSString *string = [self string];
            if ([string length] > 0) {
                // 挿入ポイントを自前で描画する
                CGFloat partialFraction;
                NSLayoutManager *layoutManager = [self layoutManager];
                NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:[self convertPoint:[dragInfo draggingLocation] fromView:nil]
                                                          inTextContainer:[self textContainer]
                                           fractionOfDistanceThroughGlyph:&partialFraction];
                NSPoint glypthIndexPoint;
                if ((partialFraction > 0.5) && ([string characterAtIndex:glyphIndex] != '\n')) {
                    NSRect glyphRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1)
                                                                inTextContainer:[self textContainer]];
                    glypthIndexPoint = [layoutManager locationForGlyphAtIndex:glyphIndex];
                    glypthIndexPoint.x += NSWidth(glyphRect);
                } else {
                    glypthIndexPoint = [layoutManager locationForGlyphAtIndex:glyphIndex];
                }
                NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];
                NSRect insertionRect = NSMakeRect(glypthIndexPoint.x, lineRect.origin.y, 1, NSHeight(lineRect));
                if (!NSEqualRects([self insertionRect], insertionRect)) {
                    // 古い自前挿入ポイントが描かれたままになることへの対応
                    [self setNeedsDisplayInRect:[self insertionRect] avoidAdditionalLayout:NO];
                }
                [[self insertionPointColor] set];
                [self lockFocus];
                NSFrameRectWithWidth(insertionRect, 1.0);
                [self unlockFocus];
                [self setInsertionRect:insertionRect];
            }
            
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}


// ------------------------------------------------------
/// ドロップ実行（同じ書類からドロップされた文字列の改行コードをLFへ置換するためにオーバーライド）
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
// ------------------------------------------------------
{
    // ドロップによる編集で改行コードをLFに統一する
    // （その他の編集は、下記の通りの別の場所で置換している）
    // # テキスト編集時の改行コードの置換場所
    //  * ファイルオープン = CEDocument > setStringToEditor
    //  * スクリプト = CEEditorView > textView:shouldChangeTextInRange:replacementString:
    //  * キー入力 = CEEditorView > textView:shouldChangeTextInRange:replacementString:
    //  * ペースト = CETextView > readSelectionFromPasteboard:type:
    //  * ドロップ（別書類または別アプリから） = CETextView > readSelectionFromPasteboard:type:
    //  * ドロップ（同一書類内） = CETextView > performDragOperation:
    //  * 検索パネルでの置換 = (OgreKit) OgreTextViewPlainAdapter > replaceCharactersInRange:withOGString:
    
    // まず、自己内ドラッグかどうかのフラグを立てる
    [self setSelfDrop:([sender draggingSource] == self)];
    
    if ([self isSelfDrop]) {
        // （自己内ドラッグの場合には、改行コード置換を readSelectionFromPasteboard:type: 内で実行すると
        // アンドゥの登録で文字列範囲の計算が面倒なので、ここでPasteboardを書き換えてしまう）
        NSPasteboard *pboard = [sender draggingPasteboard];
        NSString *pboardType = [pboard availableTypeFromArray:[CETextView pasteboardTypesForString]];
        if (pboardType) {
            NSString *string = [pboard stringForType:pboardType];
            if (string) {
                CENewLineType newlineChar = [string detectNewLineType];
                if ((newlineChar != CENewLineNone) && (newlineChar != CENewLineLF)) {
                    [pboard setString:[string stringByReplacingNewLineCharacersWith:CENewLineLF]
                              forType:pboardType];
                }
            }
        }
    }
    
    BOOL success = [super performDragOperation:sender];
    [self setSelfDrop:NO];
    
    return success;
}


// ------------------------------------------------------
/// ペーストまたはドロップされたアイテムに応じて挿入する文字列をNSPasteboardから読み込む
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard type:(NSString *)type
// ------------------------------------------------------
{
    // （このメソッドは、performDragOperation: 内で呼ばれる）
    
    BOOL success = NO;
    NSRange selectedRange, newRange;
    
    // 実行中フラグを立てる
    [self setReadingFromPboard:YES];
    
    // ペーストされたか、他からテキストがドロップされた
    if (![self isSelfDrop] && [type isEqualToString:NSStringPboardType]) {
        // ペースト、他からのドロップによる編集で改行コードをLFに統一する
        // （その他の編集は、下記の通りの別の場所で置換している）
        // # テキスト編集時の改行コードの置換場所
        //  * ファイルオープン = CEDocument > setStringToEditor
        //  * スクリプト = CEEditorView > textView:shouldChangeTextInRange:replacementString:
        //  * キー入力 = CEEditorView > textView:shouldChangeTextInRange:replacementString:
        //  * ペースト = CETextView > readSelectionFromPasteboard:type:
        //  * ドロップ（別書類または別アプリから） = CETextView > readSelectionFromPasteboard:type:
        //  * ドロップ（同一書類内） = CETextView > performDragOperation:
        //  * 検索パネルでの置換 = (OgreKit) OgreTextViewPlainAdapter > replaceCharactersInRange:withOGString:
        
        NSString *pboardStr = [pboard stringForType:NSStringPboardType];
        if (pboardStr) {
            CENewLineType newlineChar = [pboardStr detectNewLineType];
            if ((newlineChar != CENewLineNone) && (newlineChar != CENewLineLF)) {
                NSString *replacedStr = [pboardStr stringByReplacingNewLineCharacersWith:CENewLineLF];
                selectedRange = [self selectedRange];
                newRange = NSMakeRange(selectedRange.location + [replacedStr length], 0);
                // （Action名は自動で付けられる？ので、指定しない）
                [self doReplaceString:replacedStr withRange:selectedRange withSelected:newRange withActionName:@""];
                success = YES;
            }
        }
        
        // ファイルがドロップされた
    } else if ([type isEqualToString:NSFilenamesPboardType]) {
        NSArray *fileDropDefs = [[NSUserDefaults standardUserDefaults] arrayForKey:CEDefaultFileDropArrayKey];
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        NSURL *documentURL = [[[[self window] windowController] document] fileURL];
        
        for (NSString *path in files) {
            NSURL *absoluteURL = [NSURL fileURLWithPath:path];
            NSString *pathExtension = nil, *pathExtensionLower = nil, *pathExtensionUpper = nil;
            NSString *stringToDrop = nil;
            
            selectedRange = [self selectedRange];
            for (NSDictionary *definition in fileDropDefs) {
                NSArray *extensions = [definition[CEFileDropExtensionsKey] componentsSeparatedByString:@", "];
                pathExtension = [absoluteURL pathExtension];
                pathExtensionLower = [pathExtension lowercaseString];
                pathExtensionUpper = [pathExtension uppercaseString];
                
                if ([extensions containsObject:pathExtensionLower] ||
                    [extensions containsObject:pathExtensionUpper])
                {
                    stringToDrop = definition[CEFileDropFormatStringKey];
                }
            }
            if ([stringToDrop length] > 0) {
                NSString *relativePath;
                if (documentURL && ![documentURL isEqual:absoluteURL]) {
                    NSArray *docPathComponents = [documentURL pathComponents];
                    NSArray *droppedPathComponents = [absoluteURL pathComponents];
                    NSMutableArray *relativeComponents = [NSMutableArray array];
                    NSUInteger sameCount = 0, count = 0;
                    NSUInteger docCompnentsCount = [docPathComponents count];
                    NSUInteger droppedCompnentsCount = [droppedPathComponents count];
                    
                    for (NSUInteger i = 0; i < docCompnentsCount; i++) {
                        if (![docPathComponents[i] isEqualToString:droppedPathComponents[i]]) {
                            sameCount = i;
                            count = docCompnentsCount - sameCount - 1;
                            break;
                        }
                    }
                    for (NSUInteger i = count; i > 0; i--) {
                        [relativeComponents addObject:@".."];
                    }
                    for (NSUInteger i = sameCount; i < droppedCompnentsCount; i++) {
                        [relativeComponents addObject:droppedPathComponents[i]];
                    }
                    relativePath = [[NSURL fileURLWithPathComponents:relativeComponents] relativePath];
                } else {
                    relativePath = [absoluteURL path];
                }
                
                NSString *fileName = [absoluteURL lastPathComponent];
                NSString *fileNoSuffix = [fileName stringByDeletingPathExtension];
                NSString *dirName = [[absoluteURL URLByDeletingLastPathComponent] lastPathComponent];
                
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropAbsolutePathToken
                                                                       withString:[absoluteURL path]];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropRelativePathToken
                                                                       withString:relativePath];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropFilenameToken
                                                                       withString:fileName];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropFilenameNosuffixToken
                                                                       withString:fileNoSuffix];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropFileextensionToken
                                                                       withString:pathExtension];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropFileextensionLowerToken
                                                                       withString:pathExtensionLower];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropFileextensionUpperToken
                                                                       withString:pathExtensionUpper];
                stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropDirectoryToken
                                                                       withString:dirName];
                
                NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:absoluteURL];
                if (imageRep) {
                    // NSImage の size では dpi をも考慮されたサイズが返ってきてしまうので NSImageRep を使う
                    stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropImagewidthToken
                                                                           withString:[NSString stringWithFormat:@"%zd",
                                                                                       [imageRep pixelsWide]]];
                    stringToDrop = [stringToDrop stringByReplacingOccurrencesOfString:CEFileDropImagehightToken
                                                                           withString:[NSString stringWithFormat:@"%zd",
                                                                                       [imageRep pixelsHigh]]];
                }
                // （ファイルをドロップしたときは、挿入文字列全体を選択状態にする）
                newRange = NSMakeRange(selectedRange.location, [stringToDrop length]);
                // （Action名は自動で付けられる？ので、指定しない）
                [self doReplaceString:stringToDrop withRange:selectedRange withSelected:newRange withActionName:@""];
                // 挿入後、選択範囲を移動させておかないと複数オブジェクトをドロップされた時に重ね書きしてしまう
                [self setSelectedRange:NSMakeRange(NSMaxRange(newRange), 0)];
                success = YES;
            }
        }
    }
    if (!success) {
        success = [super readSelectionFromPasteboard:pboard type:type];
    }
    [self setReadingFromPboard:NO];
    
    return success;
}


// ------------------------------------------------------
/// フォントパネルを更新
- (void)updateFontPanel
// ------------------------------------------------------
{
    // フォントのみをフォントパネルに渡す
    // -> super にやらせると、テキストカラーもフォントパネルに送り、フォントパネルがさらにカラーパネル（= カラーコードパネル）にそのテキストカラーを渡すので、
    // それを断つために自分で渡す
    [[NSFontManager sharedFontManager] setSelectedFont:[self font] isMultiple:NO];
}



#pragma mark Protocol

//=======================================================
// NSKeyValueObserving Protocol
//=======================================================

// ------------------------------------------------------
/// ユーザ設定の変更を反映する
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
// ------------------------------------------------------
{
    id newValue = change[NSKeyValueChangeNewKey];
    
    if ([keyPath isEqualToString:CEDefaultAutoExpandTabKey]) {
        [self setAutoTabExpandEnabled:[newValue boolValue]];
        
    } else if ([keyPath isEqualToString:CEDefaultSmartInsertAndDeleteKey]) {
        [self setSmartInsertDeleteEnabled:[newValue boolValue]];
        
    } else if ([keyPath isEqualToString:CEDefaultCheckSpellingAsTypeKey]) {
        [self setContinuousSpellCheckingEnabled:[newValue boolValue]];
        
    } else if ([keyPath isEqualToString:CEDefaultEnableSmartQuotesKey]) {
        if ([self respondsToSelector:@selector(setAutomaticQuoteSubstitutionEnabled:)]) {  // only on OS X 10.9 and later
            [self setAutomaticQuoteSubstitutionEnabled:[newValue boolValue]];
            [self setAutomaticDashSubstitutionEnabled:[newValue boolValue]];
        }
    }
}


//=======================================================
// NSMenuValidation Protocol
//=======================================================

// ------------------------------------------------------
/// メニューの有効／無効を制御
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
// ------------------------------------------------------
{
    if (([menuItem action] == @selector(exchangeFullwidthRoman:)) ||
        ([menuItem action] == @selector(exchangeHalfwidthRoman:)) ||
        ([menuItem action] == @selector(exchangeKatakana:)) ||
        ([menuItem action] == @selector(exchangeHiragana:)) ||
        ([menuItem action] == @selector(normalizeUnicodeWithNFD:)) ||
        ([menuItem action] == @selector(normalizeUnicodeWithNFC:)) ||
        ([menuItem action] == @selector(normalizeUnicodeWithNFKD:)) ||
        ([menuItem action] == @selector(normalizeUnicodeWithNFKC:)))
    {
        return ([self selectedRange].length > 0);
        // （カラーコード編集メニューは常に有効）
        
    } else if ([menuItem action] == @selector(changeLineHeight:)) {
        [menuItem setState:(([self lineSpacing] == (CGFloat)[[menuItem title] doubleValue] - 1.0) ? NSOnState : NSOffState)];
    } else if ([menuItem action] == @selector(changeTabWidth:)) {
        [menuItem setState:(([self tabWidth] == [menuItem tag]) ? NSOnState : NSOffState)];
    } else if ([menuItem action] == @selector(showSelectionInfo:)) {
        NSString *selection = [[self string] substringWithRange:[self selectedRange]];
        return ([selection numberOfComposedCharacters] == 1);
    } else if ([menuItem action] == @selector(toggleComment:)) {
        NSString *title = [self canUncommentRange:[self selectedRange]] ? @"Uncomment Selection" : @"Comment Selection";
        [menuItem setTitle:NSLocalizedString(title, nil)];
        return ([self inlineCommentDelimiter] || [self blockCommentDelimiters]);
    }
    
    return [super validateMenuItem:menuItem];
}


//=======================================================
// NSToolbarItemValidation Protocol
//=======================================================

// ------------------------------------------------------
/// ツールバーアイコンの有効／無効を制御
- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
// ------------------------------------------------------
{
    if ([theItem action] == @selector(toggleComment:)) {
        return ([self inlineCommentDelimiter] || [self blockCommentDelimiters]);
    }
    
    return YES;
}



#pragma mark Public Methods

// ------------------------------------------------------
/// キー入力時の文字修飾辞書をセット
- (void)applyTypingAttributes
// ------------------------------------------------------
{
    [self setTypingAttributes:@{NSParagraphStyleAttributeName: [self paragraphStyle],
                                NSFontAttributeName: [self font],
                                NSForegroundColorAttributeName: [[self theme] textColor]}];
}


// ------------------------------------------------------
/// 選択文字列を置換
- (void)replaceSelectedStringTo:(NSString *)string scroll:(BOOL)needsScroll
// ------------------------------------------------------
{
    if (!string) { return; }
    
    NSRange selectedRange = [self selectedRange];
    NSString *actionName = (selectedRange.length > 0) ? @"Replace Text" : @"Insert Text";

    [self doInsertString:string
               withRange:selectedRange
            withSelected:NSMakeRange(selectedRange.location, [string length])
          withActionName:NSLocalizedString(actionName, nil)
                  scroll:needsScroll];
}


// ------------------------------------------------------
/// 全文字列を置換
- (void)replaceAllStringTo:(NSString *)string
// ------------------------------------------------------
{
    if (!string) { return; }
    
    [self doReplaceString:string
                withRange:NSMakeRange(0, [[self string] length])
             withSelected:NSMakeRange(0, [string length])
           withActionName:NSLocalizedString(@"Replace Text", nil)];
}


// ------------------------------------------------------
/// 選択文字列の後ろへ新規文字列を挿入
- (void)insertAfterSelection:(NSString *)string
// ------------------------------------------------------
{
    if (!string) { return; }

    [self doInsertString:string
               withRange:NSMakeRange(NSMaxRange([self selectedRange]), 0)
            withSelected:NSMakeRange(NSMaxRange([self selectedRange]), [string length])
          withActionName:NSLocalizedString(@"Insert Text", nil)
                  scroll:NO];
}


// ------------------------------------------------------
/// 末尾に新規文字列を追加
- (void)appendAllString:(NSString *)string
// ------------------------------------------------------
{
    if (!string) { return; }

    [self doInsertString:string
               withRange:NSMakeRange([[self string] length], 0)
            withSelected:NSMakeRange([[self string] length], [string length])
          withActionName:NSLocalizedString(@"Insert Text", nil)
                  scroll:NO];
}


// ------------------------------------------------------
/// カスタムキーバインドで文字列入力
- (void)insertCustomTextWithPatternNum:(NSInteger)patternNum
// ------------------------------------------------------
{
    if (patternNum < 0) { return; }
    
    NSArray *texts = [[NSUserDefaults standardUserDefaults] stringArrayForKey:CEDefaultInsertCustomTextArrayKey];

    if (patternNum < [texts count]) {
        NSString *string = texts[patternNum];

        [self doInsertString:string
                   withRange:[self selectedRange]
                withSelected:NSMakeRange([self selectedRange].location + [string length], 0)
              withActionName:NSLocalizedString(@"Insert Custom Text", nil)
                      scroll:YES];
    }
}


// ------------------------------------------------------
/// 行間値をセットし、テキストと行番号を再描画
- (void)setNewLineSpacingAndUpdate:(CGFloat)lineSpacing
// ------------------------------------------------------
{
    if (lineSpacing == [self lineSpacing]) { return; }
    
    NSRange range = NSMakeRange(0, [[self string] length]);
    
    [self setLineSpacing:lineSpacing];
    // テキストを再描画
    [[self layoutManager] invalidateLayoutForCharacterRange:range isSoft:NO actualCharacterRange:nil];
    [self updateLineNumberAndAdjustScroll];
}


// ------------------------------------------------------
/// 置換を実行
- (void)doReplaceString:(NSString *)string withRange:(NSRange)range
           withSelected:(NSRange)selection withActionName:(NSString *)actionName
// ------------------------------------------------------
{
    NSString *newStr = [string copy];
    NSString *curStr = [[self string] substringWithRange:range];

    // register Undo
    NSDocument *document = [[[self window] windowController] document];
    NSUndoManager *undoManager = [self undoManager];
    NSRange newRange = NSMakeRange(range.location, [string length]); // replaced range after method.

    [[undoManager prepareWithInvocationTarget:self] redoReplaceString:newStr withRange:range
                                                         withSelected:selection withActionName:actionName]; // redo in undo
    [[undoManager prepareWithInvocationTarget:self] setSelectedRange:[self selectedRange]]; // select current selection.
    [[undoManager prepareWithInvocationTarget:self] didChangeText]; // post notification.
    [[undoManager prepareWithInvocationTarget:[self textStorage]] replaceCharactersInRange:newRange withString:curStr];
    [[undoManager prepareWithInvocationTarget:document] updateChangeCount:NSChangeUndone]; // to decrement changeCount.
    if ([actionName length] > 0) {
        [undoManager setActionName:actionName];
    }
    BOOL shouldSetAttrs = ([[self string] length] == 0);
    [[self textStorage] beginEditing];
    [[self textStorage] replaceCharactersInRange:range withString:newStr];
    if (shouldSetAttrs) { // 文字列がない場合に AppleScript から文字列を追加されたときに Attributes が適用されないことへの対応
        [[self textStorage] setAttributes:[self typingAttributes]
                                    range:NSMakeRange(0, [[[self textStorage] string] length])];
    }
    [[self textStorage] endEditing];
    // テキストの編集ノーティフィケーションをポスト（ここでは NSTextStorage を編集しているため自動ではポストされない）
    [self didChangeText];
    // 選択範囲を変更、アンドゥカウントを増やす
    [self setSelectedRange:selection];
    [document updateChangeCount:NSChangeDone];
}


// ------------------------------------------------------
/// カラーリング設定を更新する
- (void)setTheme:(CETheme *)theme;
// ------------------------------------------------------
{
    [[self window] setBackgroundColor:[theme backgroundColor]];
    
    [self setBackgroundColor:[theme backgroundColor]];
    [self setTextColor:[theme textColor]];
    [self setHighlightLineColor:[theme lineHighLightColor]];
    [self setInsertionPointColor:[theme insertionPointColor]];
    [self setSelectedTextAttributes:@{NSBackgroundColorAttributeName: [theme selectionColor]}];
    
    // 背景色に合わせたスクローラのスタイルをセット
    NSInteger knobStyle = [theme isDarkTheme] ? NSScrollerKnobStyleLight : NSScrollerKnobStyleDefault;
    [[self enclosingScrollView] setScrollerKnobStyle:knobStyle];
    
    _theme = theme;
}



#pragma mark Action Messages

// ------------------------------------------------------
/// フォントをリセット
- (void)resetFont:(id)sender
// ------------------------------------------------------
{
    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:CEDefaultFontNameKey];
    CGFloat size = (CGFloat)[[NSUserDefaults standardUserDefaults] doubleForKey:CEDefaultFontSizeKey];
    
    [self setFont:[NSFont fontWithName:name size:size] ? : [NSFont systemFontOfSize:size]];
    [self updateLineNumberAndAdjustScroll];
}


// ------------------------------------------------------
/// 右へシフト
- (IBAction)shiftRight:(id)sender
// ------------------------------------------------------
{
    // 現在の選択区域とシフトする行範囲を得る
    NSRange selectedRange = [self selectedRange];
    NSRange lineRange = [[self string] lineRangeForRange:selectedRange];

    if (lineRange.length > 1) {
        lineRange.length--; // 最末尾の改行分を減ずる
    }
    // シフトするために挿入する文字列と長さを得る
    NSMutableString *shiftStr = [NSMutableString string];
    NSUInteger shiftLength = 0;
    if ([self isAutoTabExpandEnabled]) {
        NSUInteger tabWidth = [self tabWidth];
        shiftLength = tabWidth;
        while (tabWidth--) {
            [shiftStr appendString:@" "];
        }
    } else {
        shiftLength = 1;
        [shiftStr setString:@"\t"];
    }
    if (shiftLength < 1) { return; }

    // 置換する行を生成する
    NSMutableString *newLine = [NSMutableString stringWithString:[[self string] substringWithRange:lineRange]];
    NSString *newStr = [NSString stringWithFormat:@"%@%@", @"\n", shiftStr];
    NSUInteger lines = [newLine replaceOccurrencesOfString:@"\n"
                                                withString:newStr
                                                   options:0
                                                     range:NSMakeRange(0, [newLine length])];
    [newLine insertString:shiftStr atIndex:0];
    // 置換後の選択位置の調整
    NSUInteger newLocation;
    if ((lineRange.location == selectedRange.location) && (selectedRange.length > 0) &&
        ([[[self string] substringWithRange:selectedRange] hasSuffix:@"\n"]))
    {
        // 行頭から行末まで選択されていたときは、処理後も同様に選択する
        newLocation = selectedRange.location;
        lines++;
    } else {
        newLocation = selectedRange.location + shiftLength;
    }
    // 置換実行
    [self doReplaceString:newLine withRange:lineRange
             withSelected:NSMakeRange(newLocation, selectedRange.length + shiftLength * lines)
           withActionName:NSLocalizedString(@"Shift Right", nil)];
}


// ------------------------------------------------------
/// 左へシフト
- (IBAction)shiftLeft:(id)sender
// ------------------------------------------------------
{
    // 現在の選択区域とシフトする行範囲を得る
    NSRange selectedRange = [self selectedRange];
    NSRange lineRange = [[self string] lineRangeForRange:selectedRange];
    if (NSMaxRange(lineRange) == 0) { // 空行で実行された場合は何もしない
        return;
    }
    if ((lineRange.length > 1) &&  ([[self string] characterAtIndex:NSMaxRange(lineRange) - 1] == '\n')) {
        lineRange.length--; // 末尾の改行分を減ずる
    }
    // シフトするために削除するスペースの長さを得る
    NSInteger shiftLength = [self tabWidth];
    if (shiftLength < 1) { return; }

    // 置換する行を生成する
    NSArray *lines = [[[self string] substringWithRange:lineRange] componentsSeparatedByString:@"\n"];
    NSMutableString *newLine = [NSMutableString string];
    NSUInteger totalDeleted = 0;
    NSInteger newLocation = selectedRange.location, newLength = selectedRange.length;
    NSUInteger count = [lines count];

    // 選択区域を含む行をスキャンし、冒頭のスペース／タブを削除
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger numberOfDeleted = 0;
        NSMutableString *tmpLine = [lines[i] mutableCopy];
        BOOL spaceDeleted = NO;
        for (NSUInteger j = 0; j < shiftLength; j++) {
            if ([tmpLine length] == 0) {
                break;
            }
            unichar theChar = [lines[i] characterAtIndex:j];
            if (theChar == '\t') {
                if (!spaceDeleted) {
                    [tmpLine deleteCharactersInRange:NSMakeRange(0, 1)];
                    numberOfDeleted++;
                }
                break;
            } else if (theChar == ' ') {
                [tmpLine deleteCharactersInRange:NSMakeRange(0, 1)];
                numberOfDeleted++;
                spaceDeleted = YES;
            } else {
                break;
            }
        }
        // 処理後の選択区域用の値を算出
        if (i == 0) {
            newLocation -= numberOfDeleted;
            if (newLocation < (NSInteger)lineRange.location) {
                newLength -= (lineRange.location - newLocation);
                newLocation = lineRange.location;
            }
        } else {
            newLength -= numberOfDeleted;
            if (newLength < (NSInteger)lineRange.location - newLocation + (NSInteger)[newLine length]) {
                newLength = lineRange.location - newLocation + [newLine length];
            }
        }
        // 冒頭のスペース／タブを削除した行を合成
        [newLine appendString:tmpLine];
        if (i != ((NSInteger)[lines count] - 1)) {
            [newLine appendString:@"\n"];
        }
        totalDeleted += numberOfDeleted;
    }
    // シフトされなかったら中止
    if (totalDeleted == 0) { return; }
    if (newLocation < 0) {
        newLocation = 0;
    }
    if (newLength < 0) {
        newLength = 0;
    }
    // 置換実行
    [self doReplaceString:newLine withRange:lineRange
             withSelected:NSMakeRange(newLocation, newLength) withActionName:NSLocalizedString(@"Shift Left", nil)];
}


// ------------------------------------------------------
/// 選択範囲を含む行全体を選択する
- (IBAction)selectLines:(id)sender
// ------------------------------------------------------
{
    [self setSelectedRange:[[self string] lineRangeForRange:[self selectedRange]]];
}


// ------------------------------------------------------
/// タブ幅を変更する
- (IBAction)changeTabWidth:(id)sender
// ------------------------------------------------------
{
    [self setTabWidth:[sender tag]];
}


// ------------------------------------------------------
/// 半角円マークを入力
- (IBAction)inputYenMark:(id)sender
// ------------------------------------------------------
{
    [super insertText:[NSString stringWithCharacters:&kYenMark length:1]];
}


// ------------------------------------------------------
/// バックスラッシュを入力
- (IBAction)inputBackSlash:(id)sender
// ------------------------------------------------------
{
    [super insertText:@"\\"];
}


// ------------------------------------------------------
/// アウトラインメニュー選択によるテキスト選択を実行
- (IBAction)setSelectedRangeWithNSValue:(id)sender
// ------------------------------------------------------
{
    NSValue *value = [sender representedObject];
    
    if (!value) { return; }
    
    NSRange range = [value rangeValue];
    
    [self setNeedsUpdateOutlineMenuItemSelection:NO]; // 選択範囲変更後にメニュー選択項目が再選択されるオーバーヘッドを省く
    [self setSelectedRange:range];
    [self centerSelectionInVisibleArea:self];
    [[self window] makeFirstResponder:self];
}


// ------------------------------------------------------
/// 行間設定を変更
- (IBAction)changeLineHeight:(id)sender
// ------------------------------------------------------
{
    [self setNewLineSpacingAndUpdate:(CGFloat)[[sender title] doubleValue] - 1.0];  // title is line height
}


// ------------------------------------------------------
/// グリフ情報をポップオーバーで表示
- (IBAction)showSelectionInfo:(id)sender
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    NSString *selectedString = [[self string] substringWithRange:selectedRange];
    CEGlyphPopoverController *popoverController = [[CEGlyphPopoverController alloc] initWithCharacter:selectedString];
    
    if (!popoverController) { return; }
    
    NSRange glyphRange = [[self layoutManager] glyphRangeForCharacterRange:selectedRange actualCharacterRange:NULL];
    NSRect selectedRect = [[self layoutManager] boundingRectForGlyphRange:glyphRange inTextContainer:[self textContainer]];
    NSPoint containerOrigin = [self textContainerOrigin];
    selectedRect.origin.x += containerOrigin.x;
    selectedRect.origin.y += containerOrigin.y - 6.0;
    selectedRect = [self convertRectToLayer:selectedRect];
    
    [popoverController showPopoverRelativeToRect:selectedRect ofView:self];
    [self showFindIndicatorForRange:NSMakeRange(selectedRange.location, 1)];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// 変更を監視するデフォルトキー
+ (NSArray *)observedDefaultKeys
// ------------------------------------------------------
{
    return @[CEDefaultAutoExpandTabKey,
             CEDefaultSmartInsertAndDeleteKey,
             CEDefaultCheckSpellingAsTypeKey,
             CEDefaultEnableSmartQuotesKey];
}


// ------------------------------------------------------
/// 改行コード置換のための Pasteboard タイプ
+ (NSArray *)pasteboardTypesForString
// ------------------------------------------------------
{
    return @[NSPasteboardTypeString, (NSString *)kUTTypeUTF8PlainText];
}


// ------------------------------------------------------
/// ウインドウの透明設定が変更された
- (void)didWindowOpacityChange:(NSNotification *)notification
// ------------------------------------------------------
{
    // ウインドウが不透明な時は自前で背景を描画する（サブピクセルレンダリングを有効にするためには layer-backed で不透明なビューが必要）
    [self setDrawsBackground:[[self window] isOpaque]];
    
    // 半透明時にこれを有効にすると、ファイルサイズが大きいときにハングに近い状態になるため、
    // 暫定処置として不透明時にだけ有効にする。
    // 逆に不透明時に無効だと、ウインドウリサイズ時にビューが伸び縮みする (2014-10 by 1024jp)
    [[self layer] setNeedsDisplayOnBoundsChange:[[self window] isOpaque]];
    
    [self setNeedsDisplay:YES];
}


// ------------------------------------------------------
/// 文字列置換のリドゥーを登録
- (void)redoReplaceString:(NSString *)string withRange:(NSRange)range 
            withSelected:(NSRange)selection withActionName:(NSString *)actionName
// ------------------------------------------------------
{
    [[[self undoManager] prepareWithInvocationTarget:self]
        doReplaceString:string withRange:range withSelected:selection withActionName:actionName];
}


// ------------------------------------------------------
/// 置換実行
- (void)doInsertString:(NSString *)string withRange:(NSRange)range 
            withSelected:(NSRange)selection withActionName:(NSString *)actionName scroll:(BOOL)doScroll
// ------------------------------------------------------
{
    NSUndoManager *undoManager = [self undoManager];

    // 一時的にイベントごとのグループを作らないようにする
    // （でないと、グルーピングするとchangeCountが余分にカウントされる）
    [undoManager setGroupsByEvent:NO];

    // それ以前のキー入力と分離するため、グルーピング
    // CEDocument > writeWithBackupToFile:ofType:saveOperation:でも同様の処理を行っている (2008.06.01)
    [undoManager beginUndoGrouping];
    [self setSelectedRange:range];
    [super insertText:[string copy]];
    [self setSelectedRange:selection];
    if (doScroll) {
        [self scrollRangeToVisible:selection];
    }
    if ([actionName length] > 0) {
        [undoManager setActionName:actionName];
    }
    [undoManager endUndoGrouping];
    [undoManager setGroupsByEvent:YES]; // イベントごとのグループ作成設定を元に戻す
}


// ------------------------------------------------------
/// ドラッグされているアイテムのNSFilenamesPboardTypeに指定された拡張子のものが含まれているかどうかを返す
- (BOOL)draggedItemsArray:(NSArray *)items containsExtensionInExtensions:(NSArray *)extensions
// ------------------------------------------------------
{
    for (NSString *extension in extensions) {
        for (id item in items) {
            if ([[item pathExtension] isEqualToString:extension]) {
                return YES;
            }
        }
    }
    
    return NO;
}


// ------------------------------------------------------
/// 行番号更新、キャレット／選択範囲が見えるようスクロール位置を調整
- (void)updateLineNumberAndAdjustScroll
// ------------------------------------------------------
{
    // 行番号を強制的に更新（スクロール位置が調整されない時は再描画が行われないため）
    [[self lineNumberView] setNeedsDisplay:YES];
    
    // キャレット／選択範囲が見えるようにスクロール位置を調整
    [self scrollRangeToVisible:[self selectedRange]];
}


// ------------------------------------------------------
/// Pasetboard内文字列の改行コードを書類に設定されたものに置換する
- (void)replaceLineEndingToDocCharInPboard:(NSPasteboard *)pboard
// ------------------------------------------------------
{
    if (!pboard) { return; }

    CENewLineType newLineType = [[[[self window] windowController] document] lineEnding];

    if (newLineType == CENewLineLF) { return; }
    NSString *pboardType = [pboard availableTypeFromArray:[CETextView pasteboardTypesForString]];
    if (pboardType) {
        NSString *string = [pboard stringForType:pboardType];
        
        if (string) {
            [pboard setString:[string stringByReplacingNewLineCharacersWith:newLineType]
                      forType:pboardType];
        }
    }
}


// ------------------------------------------------------
/// フォントからタブ幅を計算して返す
- (CGFloat)tabIntervalFromFont:(NSFont *)font
// ------------------------------------------------------
{
    NSMutableString *widthStr = [[NSMutableString alloc] init];
    NSUInteger numberOfSpaces = [self tabWidth];
    while (numberOfSpaces--) {
        [widthStr appendString:@" "];
    }
    font = [font screenFont] ? : font;
    
    return [widthStr sizeWithAttributes:@{NSFontAttributeName:font}].width;
}


// ------------------------------------------------------
/// calculate column number at location in the line
- (NSUInteger)columnOfLocation:(NSUInteger)location expandsTab:(BOOL)expandsTab
// ------------------------------------------------------
{
    NSRange lineRange = [[self string] lineRangeForRange:NSMakeRange(location, 0)];
    NSInteger column = location - lineRange.location;
    
    // count tab width
    if (expandsTab) {
        NSString *beforeInsertion = [[self string] substringWithRange:NSMakeRange(lineRange.location, column)];
        NSUInteger numberOfTabChars = [[beforeInsertion componentsSeparatedByString:@"\t"] count] - 1;
        column += numberOfTabChars * ([self tabWidth] - 1);
    }
    
    return column;
}


// ------------------------------------------------------
/// インデントレベルを算出
- (NSUInteger)indentLevelOfString:(NSString *)string
// ------------------------------------------------------
{
    NSRange indentRange = [string rangeOfString:@"^[ \\t　]+" options:NSRegularExpressionSearch];
    
    if (indentRange.location == NSNotFound) { return 0; }
    
    NSString *indent = [string substringWithRange:indentRange];
    NSUInteger numberOfTabChars = [[indent componentsSeparatedByString:@"\t"] count] - 1;
    
    return numberOfTabChars + (([indent length] - numberOfTabChars) / [self tabWidth]);
}

@end




#pragma mark -

@implementation CETextView (WordCompletion)

#pragma mark Superclass Methods

// ------------------------------------------------------
/// 補完時の範囲を返す
- (NSRange)rangeForUserCompletion
// ------------------------------------------------------
{
    NSString *string = [self string];
    NSRange range = [super rangeForUserCompletion];
    NSCharacterSet *charSet = [self firstCompletionCharacterSet];
    
    if (!charSet || [string length] == 0) { return range; }
    
    // 入力補完文字列の先頭となりえない文字が出てくるまで補完文字列対象を広げる
    NSInteger begin = MIN(range.location, [string length] - 1);
    for (NSInteger i = begin; i >= 0; i--) {
        if ([charSet characterIsMember:[string characterAtIndex:i]]) {
            begin = i;
        } else {
            break;
        }
    }
    return NSMakeRange(begin, NSMaxRange(range) - begin);
}



// ------------------------------------------------------
/// 補完リストの表示、選択候補の入力
- (void)insertCompletion:(NSString *)word forPartialWordRange:(NSRange)charRange movement:(NSInteger)movement isFinal:(BOOL)flag
// ------------------------------------------------------
{
    NSEvent *event = [[self window] currentEvent];
    BOOL didComplete = NO;
    
    [self stopCompletionTimer];
    
    // 補完の元になる文字列を保存する
    if (![self particalCompletionWord]) {
        [self setParticalCompletionWord:[[self string] substringWithRange:charRange]];
    }
    
    // 補完リストを表示中に通常のキー入力があったら、直後にもう一度入力補完を行うためのフラグを立てる
    // （フラグは CEEditorView > textDidChange: で評価される）
    if (flag && ([event type] == NSKeyDown) && !([event modifierFlags] & NSCommandKeyMask)) {
        NSString *inputChar = [event charactersIgnoringModifiers];
        unichar theUnichar = [inputChar characterAtIndex:0];
        
        if ([inputChar isEqualToString:[event characters]]) { //キーバインディングの入力などを除外
            // アンダースコアが右矢印キーと判断されることの是正
            if (([inputChar isEqualToString:@"_"]) && (movement == NSRightTextMovement)) {
                movement = NSIllegalTextMovement;
                flag = NO;
            }
            if ((movement == NSIllegalTextMovement) &&
                (theUnichar < 0xF700) && (theUnichar != NSDeleteCharacter)) { // 通常のキー入力の判断
                [self setNeedsRecompletion:YES];
            }
        }
    }
    
    if (flag) {
        if ((movement == NSIllegalTextMovement) || (movement == NSRightTextMovement)) {  // キャンセル扱い
            // 保存していた入力を復帰する（大文字／小文字が変更されている可能性があるため）
            word = [self particalCompletionWord];
        } else {
            didComplete = YES;
        }
        
        // 補完の元になる文字列をクリア
        [self setParticalCompletionWord:nil];
    }
    
    [super insertCompletion:word forPartialWordRange:charRange movement:movement isFinal:flag];
    
    if (didComplete) {
        // 補完文字列に括弧が含まれていたら、括弧内だけを選択
        NSRange rangeToSelect = [word rangeOfString:@"(?<=\\().*(?=\\))" options:NSRegularExpressionSearch];
        if (rangeToSelect.location != NSNotFound) {
            rangeToSelect.location += charRange.location;
            [self setSelectedRange:rangeToSelect];
        }
    }
}



#pragma mark Public Methods

// ------------------------------------------------------
/// ディレイをかけて入力補完リストを表示
- (void)completeAfterDelay:(NSTimeInterval)delay
// ------------------------------------------------------
{
    if ([self completionTimer]) {
        [[self completionTimer] setFireDate:[NSDate dateWithTimeIntervalSinceNow:delay]];
    } else {
        [self setCompletionTimer:[NSTimer scheduledTimerWithTimeInterval:delay
                                                                  target:self
                                                                selector:@selector(completionWithTimer:)
                                                                userInfo:nil
                                                                 repeats:NO]];
    }
}



#pragma mark Semi-Private Methods

// ------------------------------------------------------
/// 入力補完タイマーを停止
- (void)stopCompletionTimer
// ------------------------------------------------------
{
    [[self completionTimer] invalidate];
    [self setCompletionTimer:nil];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// 入力補完リストの表示
- (void)completionWithTimer:(NSTimer *)timer
// ------------------------------------------------------
{
    [self stopCompletionTimer];
    
    // abord if input is not specified (for Japanese input)
    if ([self hasMarkedText]) { return; }
    
    // abord if selected
    if ([self selectedRange].length > 0) { return; }
    
    // abord if caret is (probably) at the middle of a word
    NSUInteger nextCharIndex = NSMaxRange([self selectedRange]);
    if (nextCharIndex < [[self string] length]) {
        unichar nextChar = [[self string] characterAtIndex:nextCharIndex];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:nextChar]) {
            return;
        }
    }
    
    // abord if previous character is blank
    NSUInteger location = [self selectedRange].location;
    if (location > 0) {
        unichar prevChar = [[self string] characterAtIndex:location - 1];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:prevChar]) {
            return;
        }
    }
    
    [self complete:self];
}

@end




#pragma mark -

@implementation CETextView (WordSelection)

#pragma mark Superclass Methods

// ------------------------------------------------------
/// adjust word selection range
- (NSRange)selectionRangeForProposedRange:(NSRange)proposedSelRange granularity:(NSSelectionGranularity)granularity
// ------------------------------------------------------
{
    // This method is partly based on Smultron's SMLTextView by Peter Borg (2006-09-09)
    // Smultron 2 was distributed on <http://smultron.sourceforge.net> under the terms of the BSD license.
    // Copyright (c) 2004-2006 Peter Borg
    
    NSString *completeString = [self string];
    
    if (granularity != NSSelectByWord || [completeString length] == proposedSelRange.location) {
        return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
    }
    
    NSRange wordRange = [super selectionRangeForProposedRange:proposedSelRange granularity:NSSelectByWord];
    
    // treat additional specific chars as separator (see wordRangeAt: for details)
    if (wordRange.length > 0) {
        wordRange = [self wordRangeAt:proposedSelRange.location];
        if (proposedSelRange.length > 1) {
            wordRange = NSUnionRange(wordRange, [self wordRangeAt:NSMaxRange(proposedSelRange) - 1]);
        }
    }
    
    // settle result on expanding selection or if there is no possibility for clicking brackets
    if (proposedSelRange.length > 0 || wordRange.length != 1) { return wordRange; }
    
    // select inside of brackets by double-clicking
    NSInteger location = wordRange.location;
    unichar beginBrace, endBrace;
    BOOL isEndBrace = NO;
    switch ([completeString characterAtIndex:location]) {
        case ')':
            isEndBrace = YES;
        case '(':
            beginBrace = '(';
            endBrace = ')';
            break;
            
        case '}':
            isEndBrace = YES;
        case '{':
            beginBrace = '{';
            endBrace = '}';
            break;
            
        case ']':
            isEndBrace = YES;
        case '[':
            beginBrace = '[';
            endBrace = ']';
            break;
            
        case '>':
            isEndBrace = YES;
        case '<':
            beginBrace = '<';
            endBrace = '>';
            break;
            
        default: {
            return wordRange;
        }
    }
    
    NSUInteger lengthOfString = [completeString length];
    NSInteger originalLocation = location;
    NSUInteger skipMatchingBrace = 0;
    
    if (isEndBrace) {
        while (location--) {
            unichar characterToCheck = [completeString characterAtIndex:location];
            if (characterToCheck == beginBrace) {
                if (!skipMatchingBrace) {
                    return NSMakeRange(location, originalLocation - location + 1);
                } else {
                    skipMatchingBrace--;
                }
            } else if (characterToCheck == endBrace) {
                skipMatchingBrace++;
            }
        }
    } else {
        while (++location < lengthOfString) {
            unichar characterToCheck = [completeString characterAtIndex:location];
            if (characterToCheck == endBrace) {
                if (!skipMatchingBrace) {
                    return NSMakeRange(originalLocation, location - originalLocation + 1);
                } else {
                    skipMatchingBrace--;
                }
            } else if (characterToCheck == beginBrace) {
                skipMatchingBrace++;
            }
        }
    }
    NSBeep();
    
    // If it has a found a "starting" brace but not found a match, a double-click should only select the "starting" brace and not what it usually would select at a double-click
    return [super selectionRangeForProposedRange:NSMakeRange(proposedSelRange.location, 1) granularity:NSSelectByCharacter];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// word range includes location
- (NSRange)wordRangeAt:(NSUInteger)location
// ------------------------------------------------------
{
    NSRange proposedWordRange = [super selectionRangeForProposedRange:NSMakeRange(location, 0) granularity:NSSelectByWord];
    
    if (proposedWordRange.length <= 1) { return proposedWordRange; }
    
    NSRange wordRange = proposedWordRange;
    NSString *word = [[self string] substringWithRange:proposedWordRange];
    NSScanner *scanner = [NSScanner scannerWithString:word];
    NSCharacterSet *breakCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@".:"];
    
    while ([scanner scanUpToCharactersFromSet:breakCharacterSet intoString:nil]) {
        NSUInteger breakLocation = [scanner scanLocation];
        
        if (proposedWordRange.location + breakLocation < location) {
            wordRange.location = proposedWordRange.location + breakLocation + 1;
            wordRange.length = proposedWordRange.length - (breakLocation + 1);
            
        } else if (proposedWordRange.location + breakLocation == location) {
            wordRange = NSMakeRange(location, 1);
            break;
            
        } else {
            wordRange.length -= proposedWordRange.length - breakLocation;
            break;
        }
        [scanner scanCharactersFromSet:breakCharacterSet intoString:nil];
    }
    
    return wordRange;
}

@end




#pragma mark -

@implementation CETextView (PinchZoomSupport)

#pragma mark Superclass Methods

// ------------------------------------------------------
/// change font size by pinch gesture
- (void)magnifyWithEvent:(NSEvent *)event
// ------------------------------------------------------
{
    BOOL isScalingDown = ([event magnification] < 0);
    CGFloat defaultSize = (CGFloat)[[NSUserDefaults standardUserDefaults] floatForKey:CEDefaultFontSizeKey];
    CGFloat size = [[self font] pointSize];
    
    // avoid scaling down to smaller than default size
    if (isScalingDown && size == defaultSize) { return; }
    
    // calc new font size
    size = MAX(defaultSize, size + ([event magnification] * 10));
    
    [self changeFontSize:size];
}


// ------------------------------------------------------
/// reset font size by two-finger double tap
- (void)smartMagnifyWithEvent:(NSEvent *)event
// ------------------------------------------------------
{
    CGFloat defaultSize = (CGFloat)[[NSUserDefaults standardUserDefaults] floatForKey:CEDefaultFontSizeKey];
    CGFloat size = [[self font] pointSize];
    
    if (size == defaultSize) {
        // pseudo-animation
        for (CGFloat factor = 1, interval = 0; factor <= 1.5; factor += 0.05, interval += 0.01) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self changeFontSize:size * factor];
            });
        }
    } else {
        [self changeFontSize:defaultSize];
    }
}



#pragma mark Private Methods

// ------------------------------------------------------
/// change font size keeping visible area as possible
- (void)changeFontSize:(CGFloat)size
// ------------------------------------------------------
{
    // store current visible area
    NSRange glyphRange = [[self layoutManager] glyphRangeForBoundingRect:[self visibleRect]
                                                         inTextContainer:[self textContainer]];
    NSRange visibleRange = [[self layoutManager] characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
    NSRange selectedRange = [self selectedRange];
    selectedRange.length = MAX(selectedRange.length, 1);  // sanitize for NSIntersectionRange()
    BOOL isSelectionVisible = (NSIntersectionRange(visibleRange, selectedRange).length > 0);
    
    // change font size
    [self setFont:[[NSFontManager sharedFontManager] convertFont:[self font] toSize:size]];
    
    // adjust visible area
    [self scrollRangeToVisible:visibleRange];
    if (isSelectionVisible) {
        [self scrollRangeToVisible:selectedRange];
    }
    
    // force redraw line number view
    [[self lineNumberView] setNeedsDisplay:YES];
}

@end




#pragma mark -

@implementation CETextView (Commenting)

#pragma mark Action Messages

// ------------------------------------------------------
/// toggle comment state in selection
- (IBAction)toggleComment:(id)sender
// ------------------------------------------------------
{
    if ([self canUncommentRange:[self selectedRange]]) {
        [self uncomment:sender];
    } else {
        [self commentOut:sender];
    }
}


// ------------------------------------------------------
/// comment out selection appending comment delimiters
- (IBAction)commentOut:(id)sender
// ------------------------------------------------------
{
    if (![self blockCommentDelimiters] && ![self inlineCommentDelimiter]) { return; }
    
    // determine comment out target
    NSRange targetRange;
    if (![sender isKindOfClass:[NSScriptCommand class]] &&
        [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultCommentsAtLineHeadKey])
    {
        targetRange = [[self string] lineRangeForRange:[self selectedRange]];
    } else {
        targetRange = [self selectedRange];
    }
    // remove last return
    if (targetRange.length > 0 && [[self string] characterAtIndex:NSMaxRange(targetRange) - 1] == '\n') {
        targetRange.length--;
    }
    
    NSString *target = [[self string] substringWithRange:targetRange];
    NSString *beginDelimiter, *endDelimiter;
    NSString *spacer = [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultAppendsCommentSpacerKey] ? @" " : @"";
    NSString *newString;
    NSRange selected;
    NSUInteger addedChars = 0;
    
    // insert delimiters
    if ([self inlineCommentDelimiter]) {
        beginDelimiter = [self inlineCommentDelimiter];
        
        newString = [target stringByReplacingOccurrencesOfString:@"\n"
                                                      withString:[NSString stringWithFormat:@"\n%@%@", beginDelimiter, spacer]
                                                         options:0
                                                           range:NSMakeRange(0, [target length])];
        newString = [@[beginDelimiter, newString] componentsJoinedByString:spacer];
        addedChars = [newString length] - targetRange.length;
        
    } else if ([self blockCommentDelimiters]) {
        beginDelimiter = [self blockCommentDelimiters][CEBeginDelimiterKey];
        endDelimiter = [self blockCommentDelimiters][CEEndDelimiterKey];
        
        newString = [@[beginDelimiter, target, endDelimiter] componentsJoinedByString:spacer];
        addedChars = [beginDelimiter length] + [spacer length];
    }
    
    // selection
    if ([self selectedRange].length > 0) {
        selected = NSMakeRange(targetRange.location, [newString length]);
    } else {
        selected = NSMakeRange([self selectedRange].location + addedChars, 0);
    }
    
    // replace
    [self doReplaceString:newString
                withRange:targetRange
             withSelected:selected
           withActionName:NSLocalizedString(@"Comment Out", nil)];
}


// ------------------------------------------------------
/// uncomment selection removing comment delimiters
- (IBAction)uncomment:(id)sender
// ------------------------------------------------------
{
    if (![self blockCommentDelimiters] && ![self inlineCommentDelimiter]) { return; }
    
    BOOL hasUncommented = NO;
    
    // determine uncomment target
    NSRange targetRange;
    if (![sender isKindOfClass:[NSScriptCommand class]] &&
        [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultCommentsAtLineHeadKey])
    {
        targetRange = [[self string] lineRangeForRange:[self selectedRange]];
    } else {
        targetRange = [self selectedRange];
    }
    // remove last return
    if (targetRange.length > 0 && [[self string] characterAtIndex:NSMaxRange(targetRange) - 1] == '\n') {
        targetRange.length--;
    }
    
    NSString *target = [[self string] substringWithRange:targetRange];
    NSString *beginDelimiter, *endDelimiter;
    NSString *spacer = [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultAppendsCommentSpacerKey] ? @" " : @"";
    NSString *newString;
    NSUInteger removedChars = 0;
    
    // block comment
    if ([self blockCommentDelimiters]) {
        if ([target length] > 0) {
            beginDelimiter = [self blockCommentDelimiters][CEBeginDelimiterKey];
            endDelimiter = [self blockCommentDelimiters][CEEndDelimiterKey];
            
            // remove comment delimiters
            if ([target hasPrefix:beginDelimiter] && [target hasSuffix:endDelimiter]) {
                removedChars = [beginDelimiter length];
                newString = [target substringWithRange:NSMakeRange([beginDelimiter length],
                                                                   [target length] - [beginDelimiter length] - [endDelimiter length])];
                
                if ([spacer length] > 0 && [newString hasPrefix:spacer] && [newString hasSuffix:spacer]) {
                    newString = [newString substringWithRange:NSMakeRange(1, [newString length] - 2)];
                    removedChars++;
                }
                
                hasUncommented = YES;
            }
        }
    }
    
    // inline comment
    beginDelimiter = [self inlineCommentDelimiter];
    if (!hasUncommented && beginDelimiter) {
        
        // remove comment delimiters
        NSArray *lines = [target componentsSeparatedByString:@"\n"];
        NSMutableArray *newLines = [NSMutableArray array];
        for (NSString *line in lines) {
            NSString *newLine = [line copy];
            if ([line hasPrefix:beginDelimiter]) {
                newLine = [line substringFromIndex:[beginDelimiter length]];
                
                if ([spacer length] > 0 && [newLine hasPrefix:spacer]) {
                    newLine = [newLine substringFromIndex:[spacer length]];
                }
                
                hasUncommented = YES;
            }
            
            [newLines addObject:newLine];
            removedChars += [line length] - [newLine length];
        }
        
        newString = [newLines componentsJoinedByString:@"\n"];
    }
    
    if (!hasUncommented) { return; }
    
    // set selection
    NSRange selection;
    if ([self selectedRange].length > 0) {
        selection = NSMakeRange(targetRange.location, [newString length]);
    } else {
        selection = NSMakeRange([self selectedRange].location, 0);
        selection.location -= MIN(MIN(selection.location, selection.location - targetRange.location), removedChars);
    }
    
    [self doReplaceString:newString withRange:targetRange withSelected:selection
           withActionName:NSLocalizedString(@"Uncomment", nil)];
}



#pragma mark Semi-Private Methods

// ------------------------------------------------------
/// whether given range can be uncommented
- (BOOL)canUncommentRange:(NSRange)range
// ------------------------------------------------------
{
    if (![self blockCommentDelimiters] && ![self inlineCommentDelimiter]) { return NO; }
    
    // determine comment out target
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultCommentsAtLineHeadKey]) {
        range = [[self string] lineRangeForRange:range];
    }
    // remove last return
    if (range.length > 0 && [[self string] characterAtIndex:NSMaxRange(range) - 1] == '\n') {
        range.length--;
    }
    
    NSString *target = [[self string] substringWithRange:range];
    
    if ([target length] == 0) { return NO; }
    
    if ([self blockCommentDelimiters]) {
        if ([target hasPrefix:[self blockCommentDelimiters][CEBeginDelimiterKey]] &&
            [target hasSuffix:[self blockCommentDelimiters][CEEndDelimiterKey]]) {
            return YES;
        }
    }
    
    if ([self inlineCommentDelimiter]) {
        NSArray *lines = [target componentsSeparatedByString:@"\n"];
        NSUInteger commentLineCount = 0;
        for (NSString *line in lines) {
            if ([line hasPrefix:[self inlineCommentDelimiter]]) {
                commentLineCount++;
            }
        }
        
        return commentLineCount == [lines count];
    }
    
    return NO;
}

@end




#pragma mark -

@implementation CETextView (UtilityMenu)

// enum
typedef NS_ENUM(NSUInteger, CEUnicodeNormalizationForm) {
    CEUnicodeNormalizationNFD,
    CEUnicodeNormalizationNFC,
    CEUnicodeNormalizationNFKD,
    CEUnicodeNormalizationNFKC
};


#pragma mark Action Messages

// ------------------------------------------------------
/// transform half-width roman characters in selection to full-width
- (IBAction)exchangeFullwidthRoman:(id)sender
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    
    if (selectedRange.length == 0) { return; }
    
    NSString *newStr =  [[[self string] substringWithRange:selectedRange] fullWidthRomanString];
    if (newStr) {
        [self doInsertString:newStr withRange:selectedRange
                withSelected:NSMakeRange(selectedRange.location, [newStr length])
              withActionName:NSLocalizedString(@"To Fullwidth Roman", nil) scroll:YES];
    }
}


// ------------------------------------------------------
/// transform full-width roman characters in selection to half-width
- (IBAction)exchangeHalfwidthRoman:(id)sender
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    
    if (selectedRange.length == 0) { return; }
    
    NSString *newStr =  [[[self string] substringWithRange:selectedRange] halfWidthRomanString];
    if (newStr) {
        [self doInsertString:newStr withRange:selectedRange
                withSelected:NSMakeRange(selectedRange.location, [newStr length])
              withActionName:NSLocalizedString(@"To Halfwidth Roman", nil) scroll:YES];
    }
}


// ------------------------------------------------------
/// transform Hiragana in selection to Katakana
- (IBAction)exchangeKatakana:(id)sender
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    
    if (selectedRange.length == 0) { return; }
    
    NSString *newStr =  [[[self string] substringWithRange:selectedRange] katakanaString];
    if (newStr) {
        [self doInsertString:newStr withRange:selectedRange
                withSelected:NSMakeRange(selectedRange.location, [newStr length])
              withActionName:NSLocalizedString(@"Hiragana to Katakana",@"") scroll:YES];
    }
}


// ------------------------------------------------------
/// transform Katakana in selection to Hiragana
- (IBAction)exchangeHiragana:(id)sender
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    
    if (selectedRange.length == 0) { return; }
    
    NSString *newStr = [[[self string] substringWithRange:selectedRange] hiraganaString];
    if (newStr) {
        [self doInsertString:newStr withRange:selectedRange
                withSelected:NSMakeRange(selectedRange.location, [newStr length])
              withActionName:NSLocalizedString(@"Katakana to Hiragana",@"") scroll:YES];
    }
}


// ------------------------------------------------------
/// Unicode normalization (NDF)
- (IBAction)normalizeUnicodeWithNFD:(id)sender
// ------------------------------------------------------
{
    [self normalizeUnicodeWithForm:CEUnicodeNormalizationNFD];
}


// ------------------------------------------------------
/// Unicode normalization (NFC)
- (IBAction)normalizeUnicodeWithNFC:(id)sender
// ------------------------------------------------------
{
    [self normalizeUnicodeWithForm:CEUnicodeNormalizationNFC];
}


// ------------------------------------------------------
/// Unicode normalization (NFKD)
- (IBAction)normalizeUnicodeWithNFKD:(id)sender
// ------------------------------------------------------
{
    [self normalizeUnicodeWithForm:CEUnicodeNormalizationNFKD];
}


// ------------------------------------------------------
/// Unicode normalization (NFKC)
- (IBAction)normalizeUnicodeWithNFKC:(id)sender
// ------------------------------------------------------
{
    [self normalizeUnicodeWithForm:CEUnicodeNormalizationNFKC];
}


// ------------------------------------------------------
/// tell selected string to color code panel
- (IBAction)editColorCode:(id)sender
// ------------------------------------------------------
{
    NSString *selectedString = [[self string] substringWithRange:[self selectedRange]];
    
    [[CEColorCodePanelController sharedController] showWindow:sender];
    [[CEColorCodePanelController sharedController] setColorWithCode:selectedString];
}


// ------------------------------------------------------
/// avoid changeing text color by color panel
- (IBAction)changeColor:(id)sender
// ------------------------------------------------------
{
    // do nothing.
}



#pragma mark Private Methods

// ------------------------------------------------------
/// Unicode normalization
- (void)normalizeUnicodeWithForm:(CEUnicodeNormalizationForm)form
// ------------------------------------------------------
{
    NSRange selectedRange = [self selectedRange];
    
    if (selectedRange.length == 0) { return; }
    
    NSString *originalStr = [[self string] substringWithRange:selectedRange];
    NSString *actionName = nil, *newStr = nil;
    
    switch (form) {
        case CEUnicodeNormalizationNFD:
            newStr = [originalStr decomposedStringWithCanonicalMapping];
            actionName = @"NFD";
            break;
        case CEUnicodeNormalizationNFC:
            newStr = [originalStr precomposedStringWithCanonicalMapping];
            actionName = @"NFC";
            break;
        case CEUnicodeNormalizationNFKD:
            newStr = [originalStr decomposedStringWithCompatibilityMapping];
            actionName = @"NFKD";
            break;
        case CEUnicodeNormalizationNFKC:
            newStr = [originalStr precomposedStringWithCompatibilityMapping];
            actionName = @"NFKC";
            break;
    }
    
    if (newStr) {
        [self doInsertString:newStr
                   withRange:selectedRange
                withSelected:NSMakeRange(selectedRange.location, [newStr length])
              withActionName:NSLocalizedString(actionName, nil)
                      scroll:YES];
    }
}

@end
