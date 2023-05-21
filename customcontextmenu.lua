local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local CustomContextMenu = FocusManager:extend{}

local function make_button(text, width, cb, enabled_func)
    enabled_func = enabled_func or function() return true end
    return Button:new{
        text = text,
        radius = 0,
        margin = 2,
        enabled_func = enabled_func,
        width = width,
        show_parent = CustomContextMenu,
        callback = cb,
    }
end

function CustomContextMenu:init()
    self:reset() -- first call is just for initializing
    self.font_size = 19
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = screen_width,
                    h = screen_height,
                }
            },
        }
    end

    local row_span = VerticalSpan:new{ width = Size.padding.fullscreen }
    local frame_width = math.floor(math.min(screen_width, screen_height) * 0.85)
    local frame_border_size = Size.border.window
    local frame_padding = Size.padding.fullscreen
    local inner_width = frame_width - 2 * (frame_border_size + frame_padding)

    self.scroll_widget = ScrollHtmlWidget:new{
        default_font_size = Screen:scaleBySize(self.font_size),
        width = inner_width,
        height = 150,
        dialog = self,
    }
    local button_span_unit_width = Size.span.horizontal_small
    local larger_span_units = 3 -- 3 x small span width
    local nb_span_units = 2 + 2*larger_span_units
    local btn_width = math.floor( ((inner_width+frame_padding) - nb_span_units * button_span_unit_width) * (1/6))

    -- create some helper functions
    local update = function(opts)
        self.prev_c_cnt = opts.prev_c or self.prev_c_cnt
        self.prev_s_cnt = opts.prev_s or self.prev_s_cnt
        self.next_c_cnt = opts.next_c or self.next_c_cnt
        self.next_s_cnt = opts.next_s or self.next_s_cnt
        self:update_context()
    end
    local can_prepend = function() return self.note.has_prepended_content end
    local can_append = function() return self.note.has_appended_content end
    local prev_c_inc = function(inc) update({ prev_c = self.prev_c_cnt + inc}) end
    local next_c_inc = function(inc) update({ next_c = self.next_c_cnt + inc}) end
    -- char counter is reset to 0 when sentence count is changed
    local prev_s_inc = function(inc) update({ prev_c = 0, prev_s = self.prev_s_cnt + inc}) end
    local next_s_inc = function(inc) update({ next_c = 0, next_s = self.next_s_cnt + inc}) end

    local remove_prev_sentence = make_button("⏪", btn_width, function() prev_s_inc(-1) end, can_prepend)
    local remove_prev_char =     make_button("-1", btn_width, function() prev_c_inc(-1) end, can_prepend)
    local append_prev_char =     make_button("1+", btn_width, function() prev_c_inc(1) end)
    local append_prev_sentence = make_button("⏩", btn_width, function() prev_s_inc(1) end)
    local reset_prev =           make_button("Reset", btn_width*2, function() self:reset_prev(); return self:update_context() end)

    local remove_next_sentence = make_button("⏪", btn_width, function() next_s_inc(-1) end, can_append)
    local remove_next_char =     make_button("-1", btn_width, function() next_c_inc(-1) end, can_append)
    local append_next_char =     make_button("1+", btn_width, function() next_c_inc(1) end)
    local append_next_sentence = make_button("⏩", btn_width, function() next_s_inc(1) end)
    local reset_next =           make_button("Reset", btn_width*2, function() self:reset_next(); self:update_context() end)

    self.top_row = HorizontalGroup:new{
        align = "center",
    remove_prev_sentence,
    remove_prev_char,
    reset_prev,
    append_prev_char,
    append_prev_sentence,
    }

    self.bottom_row = HorizontalGroup:new{
        align = "center",
    remove_next_sentence,
    remove_next_char,
    reset_next,
    append_next_char,
    append_next_sentence,
    }

    self.confirm_row = HorizontalGroup:new{
        align = "center",
        make_button("Cancel", btn_width*2, function() self:onClose() end),
        make_button("Save with custom context", btn_width*4, self.on_save_cb),
    }

    self.context_menu = FrameContainer:new{
        margin = 0,
        bordersize = frame_border_size,
        padding = Size.padding.default,
        radius = Size.radius.window,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            self.top_row,
            self.scroll_widget,
            row_span,
            self.bottom_row,
            self.confirm_row,
        }
    }
    self.movable = MovableContainer:new{
        self.context_menu,
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = screen_width,
            h = screen_height,
        },
        self.movable,
        self.confirm_row,
    }
    self:update_context()
end

function CustomContextMenu:onClose()
    UIManager:close(self)
end

-- used to assure we do a repaint when the menu is closed
function CustomContextMenu:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "flashui", self.context_menu.dimen
    end)
end

-- used to repaint widget when the text is changed
function CustomContextMenu:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function CustomContextMenu:onTap(_, ges_ev)
    if not ges_ev.pos:intersectWith(self.context_menu.dimen) then
        self:onClose()
    end
end

function CustomContextMenu:reset()
    self:reset_prev()
    self:reset_next()
end

function CustomContextMenu:reset_prev()
    self.prev_s_cnt = 1
    self.prev_c_cnt = 0
end

function CustomContextMenu:reset_next()
    self.next_s_cnt = 1
    self.next_c_cnt = 0
end

function CustomContextMenu:update_context()
    local prev, next_ = self.note:get_custom_context(self.prev_s_cnt, self.prev_c_cnt, self.next_s_cnt, self.next_c_cnt)
    local css = [[
        h2 {
            display: inline;
        }
        .lookupword {
            display: inline;
            font-weight: bold;
            background-color: red;
            text-align: center;
        }
        @page {
            margin: 0;
            font-family: 'Noto Sans CJK';
        }
    ]]
    local context_fmt = '<div lang="ja"><p>%s<h2 class="lookupword">%s</h2>%s</p></div>'
    local context = context_fmt:format(prev, self.note.popup_dict.word, next_)

    self[1]:free()
    self.scroll_widget.htmlbox_widget:setContent(context, css, Screen:scaleBySize(self.font_size))
    self.scroll_widget:resetScroll()
    self:onShow()
end

return CustomContextMenu
