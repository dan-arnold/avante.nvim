local Base = require("avante.llm_tools.base")
local Config = require("avante.config")
local Highlights = require("avante.highlights")
local Line = require("avante.ui.line")

---@alias AskFollowupQuestionInput {question: string, options?: string[]}

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "ask_followup_question"

M.description = [[
Use this to ask the user a clarifying question and pause for their answer, when you genuinely need information from them before you can proceed (e.g. they asked you to check with them first, or the task is ambiguous between multiple valid approaches). This is the ONLY tool that ends a turn without the task being complete -- unlike attempt_completion, using this tool does NOT mean the job is done, it means you are waiting on the user.
Do not use this as a substitute for using other tools to find information yourself. Only ask when the answer genuinely cannot be determined from the codebase, docs, or other tools available to you.
Ask about exactly ONE decision per call. If you have several things to ask, pick the single most important/blocking one now -- do not bundle multiple separate questions into one `question` string or try to cover more than one decision with a single `options` list. You will get another chance to call this tool again once the user answers this one.
]]

M.support_streaming = true

M.enabled = function() return Config.mode == "agentic" end

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "question",
      description = "The question to ask the user. Should be clear and specific about what you need to know to proceed.",
      type = "string",
    },
    {
      name = "options",
      description = "Optional list of 2-5 suggested answers to the single question above. Only include this if there's a concrete, discrete set of choices for that one question; omit it for open-ended questions. Every option must be a valid, self-contained answer to `question` -- never use this to sneak in answers to a second, different question.",
      type = "array",
      items = {
        name = "option",
        type = "string",
      },
      optional = true,
    },
  },
  usage = {
    question = "The question to ask the user. Should be clear and specific about what you need to know to proceed.",
    options = "Optional list of 2-5 suggested answers to that single question.",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "Whether the question was presented successfully",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the question could not be presented",
    type = "string",
    optional = true,
  },
}

---@type avante.LLMToolOnRender<AskFollowupQuestionInput>
function M.on_render(input)
  local lines = {}
  table.insert(lines, Line:new({ { "❓ Question", Highlights.AVANTE_TASK_COMPLETED } }))
  table.insert(lines, Line:new({ { "" } }))
  local question = input.question or ""
  local text_lines = vim.split(question, "\n")
  for _, text_line in ipairs(text_lines) do
    table.insert(lines, Line:new({ { text_line } }))
  end
  if input.options and input.options ~= vim.NIL and #input.options > 0 then
    table.insert(lines, Line:new({ { "" } }))
    for _, option in ipairs(input.options) do
      table.insert(lines, Line:new({ { "  - " .. option } }))
    end
  end
  return lines
end

---@type AvanteLLMToolFunc<AskFollowupQuestionInput>
function M.func(input, opts)
  if not opts.on_complete then return false, "on_complete not provided" end

  local is_streaming = opts.streaming or false
  if is_streaming then
    -- wait for stream completion, input may not be complete yet
    return
  end

  opts.session_ctx.ask_followup_question_is_called = true
  opts.on_complete(true, nil)

  if input.options and input.options ~= vim.NIL and #input.options > 0 then
    local options = input.options
    vim.schedule(function()
      local sidebar = require("avante").get()
      if not sidebar then return end
      vim.ui.select(options, {
        prompt = input.question or "Pick an option:",
      }, function(choice)
        if not choice then return end
        sidebar:set_input_value(choice)
        sidebar:focus_input()
      end)
    end)
  end
end

return M
