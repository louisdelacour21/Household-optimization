!##############################################################################
! MODULE globals
!
! This code is published under the GNU General Public License v3
!                         (https://www.gnu.org/licenses/gpl-3.0.en.html)
!
! Author : Louis Delacour
!
!##############################################################################
module globals

    use toolbox

    implicit none

    ! number of transition periods
    integer, parameter :: TT = 40

    ! number of years the household lives
    integer, parameter :: JJ = 12

    ! number of years the household retires
    integer, parameter :: JR = 10

    ! number of persistent shock process values
    integer, parameter :: NP = 2

    ! number of transitory shock process values
    integer, parameter :: NS = 5

    ! number of points on the asset grid
    integer, parameter :: NA = 100

    ! household preference parameters
    real*8, parameter :: gamma = 0.50d0
    real*8, parameter :: egam = 1d0 - 1d0/gamma
    real*8, parameter :: nu    = 0.335d0
    real*8, parameter :: beta  = 0.998**5

    ! household risk process
    real*8, parameter :: sigma_theta = 0.23d0
    real*8, parameter :: sigma_eps   = 0.05d0
    real*8, parameter :: rho         = 0.98d0

    ! production parameters
    real*8, parameter :: alpha = 0.36d0
    real*8, parameter :: delta = 1d0-(1d0-0.0823d0)**5
    real*8, parameter :: Omega = 1.60d0

    ! size of the asset grid
    real*8, parameter :: a_l    = 0.0d0
    real*8, parameter :: a_u    = 35d0
    real*8, parameter :: a_grow = 0.05d0

    ! demographic parameters
    real*8, parameter :: n_p   = (1d0+0.01d0)**5-1d0

    ! simulation parameters
    real*8, parameter :: damp    = 0.50d0
    real*8, parameter :: sig     = 1d-4
    integer, parameter :: itermax = 70

    ! counter variables
    integer :: iter

    ! macroeconomic variables
    real*8 :: r(0:TT), rn(0:TT), w(0:TT), wn(0:TT), p(0:TT)
    real*8 :: KK(0:TT), AA(0:TT), BB(0:TT), LL(0:TT), HH(0:TT)
    real*8 :: YY(0:TT), CC(0:TT), II(0:TT), GG(0:TT), INC(0:TT), YTAX(0:TT)

    ! government variables
    real*8 :: tauc(0:TT), tauw(0:TT), taur(0:TT), tauy(0:TT), try(0:TT), Tr(0:TT)
    real*8 :: gy, by, taup(0:TT), kappa(0:TT), pen(JJ,0:TT), PP(0:TT), taxrev(6,0:TT)
    integer :: tax(0:TT)

    ! LSRA variables
    real*8 :: BA(0:TT) = 0d0, SV(0:TT) = 0d0, lsra_comp, lsra_all, Lstar
    logical :: lsra_on

    ! cohort aggregate variables
    real*8 :: c_coh(JJ, 0:TT), l_coh(JJ, 0:TT), y_coh(JJ, 0:TT), a_coh(JJ, 0:TT)
    real*8 :: ytax_coh(JJ,0:TT), v_coh(JJ, 0:TT) = 0d0, VV_coh(JJ, 0:TT) = 0d0

    ! the shock process
    real*8 :: dist_theta(NP), theta(NP)
    real*8 :: pi(NS, NS), eta(NS)
    integer :: is_initial = 3

    ! demographic and other model parameters
    real*8 :: m(JJ, 0:TT), pop(JJ, 0:TT), eff(JJ), workpop(0:TT)

    ! individual variables
    real*8 :: a(0:NA), aplus(JJ, 0:NA, NP, NS, 0:TT)
    real*8 :: c(JJ, 0:NA, NP, NS, 0:TT), l(JJ, 0:NA, NP, NS, 0:TT)
    real*8 :: phi(JJ, 0:NA, NP, NS, 0:TT), VV(JJ, 0:NA, NP, NS, 0:TT) = 0d0
    real*8 :: v(JJ, 0:NA, NP, NS, 0:TT) = 0d0, FLC(JJ,0:TT)

    ! numerical variables
    real*8 :: RHS(JJ, 0:NA, NP, NS, 0:TT), EV(JJ, 0:NA, NP, NS, 0:TT)
    integer :: ij_com, ia_com, ip_com, is_com, it_com
    real*8 :: cons_com, lab_com, DIFF(0:TT)

contains


    ! the first order condition
    function foc(x_in)

        implicit none
        real*8, intent(in) :: x_in
        real*8 :: foc, a_plus, varphi, tomorrow, wage, v_ind, available
        integer :: ial, iar, itp

        ! calculate tomorrows assets
        a_plus  = x_in

        ! get tomorrows year
        itp = year(it_com, ij_com, ij_com+1)

        ! get lsra transfer payment
        v_ind = v(ij_com, ia_com, ip_com, is_com, it_com)

        ! calculate the wage rate
        wage = wn(it_com)*eff(ij_com)*theta(ip_com)*eta(is_com)

        ! calculate available resources
        available = (1d0+rn(it_com))*a(ia_com) + pen(ij_com, it_com) + tauy(it_com)*try(it_com) + v_ind

        ! determine labor
        if(ij_com < JR)then
            available = available + Tr(it_com)
            lab_com = min( max( nu + (1d0-nu)*(a_plus-available)/wage, 0d0) , 1d0-1d-10)
        else
            lab_com = 0d0
        endif

        ! calculate consumption
        cons_com = max( (available + wage*lab_com - a_plus)/p(it_com) , 1d-10)

        ! calculate linear interpolation for future part of first order condition
        call linint_Grow(a_plus, a_l, a_u, a_grow, NA, ial, iar, varphi)

        tomorrow = max(varphi*RHS(ij_com+1, ial, ip_com, is_com, itp) + &
                            (1d0-varphi)*RHS(ij_com+1, iar, ip_com, is_com, itp), 0d0)

        ! calculate first order condition for consumption
        foc = margu(cons_com, lab_com, it_com)**(-gamma) - tomorrow

    end function


    ! calculates marginal utility of consumption
    function margu(cons, lab, it)

        implicit none
        real*8, intent(in) :: cons, lab
        integer, intent(in) :: it
        real*8 :: margu

        margu = nu*(cons**nu*(1d0-lab)**(1d0-nu))**egam/(p(it)*cons)

    end function


    ! calculates the value function
    function valuefunc(a_plus, cons, lab, ij, ip, is, it)

        implicit none
        integer, intent(in) :: ij, ip, is, it
        real*8, intent(in) :: a_plus, cons, lab
        real*8 :: valuefunc, varphi, c_help, l_help
        integer :: ial, iar, itp

        ! check whether consumption or leisure are too small
        c_help = max(cons, 1d-10)
        l_help = min(max(lab, 0d0),1d0-1d-10)

        ! get tomorrows year
        itp = year(it, ij, ij+1)

        ! get tomorrows utility
        call linint_Grow(a_plus, a_l, a_u, a_grow, NA, ial, iar, varphi)

        ! calculate tomorrow's part of the value function
        valuefunc = 0d0
        if(ij < JJ)then
            valuefunc = max(varphi*EV(ij+1, ial, ip, is, itp) + &
                (1d0-varphi)*EV(ij+1, iar, ip, is, itp), 1d-10)**egam/egam
        endif

        ! add todays part and discount
        valuefunc = (c_help**nu*(1d0-l_help)**(1d0-nu))**egam/egam + beta*valuefunc

    end function


    ! calculates year at which age ij agent is ijp
    function year(it, ij, ijp)

        implicit none
        integer, intent(in) :: it, ij, ijp
        integer :: year

        year = it + ijp - ij

        if(it == 0 .or. year <= 0)year = 0
        if(it == TT .or. year >= TT)year = TT

    end function

end module
