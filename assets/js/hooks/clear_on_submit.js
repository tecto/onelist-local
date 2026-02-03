// Clear form input after successful LiveView submit
const ClearOnSubmit = {
  mounted() {
    this.el.addEventListener("submit", () => {
      // Reset form after a brief delay to let LiveView process
      setTimeout(() => {
        this.el.reset()
      }, 50)
    })
  }
}

export default ClearOnSubmit
