module ApplicationHelper
  def back_arrow_to(path, label:)
    link_to path, class: "back-arrow", aria: { label: label }, title: label do
      tag.span("\u2190", aria: { hidden: true })
    end
  end
end
