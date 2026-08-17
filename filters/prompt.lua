function Div(el)
  if not el.classes:includes("prompt") then
    return nil
  end

  return el:walk({
    SoftBreak = function()
      return pandoc.LineBreak()
    end
  })
end
