package dev.scrcpyconnect.scrcpy_connect

/** 无需构造框架桩即可测试生产系统所有权适配。 */
object NativeOwnershipTest {
    @JvmStatic fun main(args: Array<String>) {
        val owner = AudioPlatformOwnership()
        val firstActivity = Any()
        val replacementActivity = Any()
        check(owner.visible(firstActivity, true))
        check(!owner.visible(replacementActivity, true))
        check(!owner.visible(firstActivity, false) && owner.visible)
        check(owner.claim("first-engine"))
        val first = owner.nextEpoch()
        check(!owner.claim("other-engine"))
        check(owner.visible(replacementActivity, false) && !owner.visible)
        check(owner.epoch == first) // Activity 丢失不释放系统租约。
        check(!owner.clearEpoch(first + 1) && owner.epoch == first)
        owner.background = true
        check(owner.clearEpoch(first))
        owner.releaseIfUnused()
        check(owner.owner == "first-engine") // 仍拥有真实前台服务请求。
        owner.background = false
        owner.releaseIfUnused()
        check(owner.claim("new-engine"))
        val next = owner.nextEpoch()
        check(next > first)
        check(!owner.clearEpoch(first) && owner.epoch == next)
        check(!owner.claim("first-engine")) // 迟到的旧所有者不能取得新租约。
        check(owner.clearEpoch(next))
        owner.releaseIfUnused()
        check(owner.owner == null)
        println("PASS: Activity visibility aggregation, owner refusal, background ownership and stale epoch isolation")
    }
}
